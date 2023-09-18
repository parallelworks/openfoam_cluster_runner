#!/bin/bash
date
# Resource label
export rlabel=ofhost
export job_dir=$(pwd | rev | cut -d'/' -f1-2 | rev)
export job_id=$(echo ${job_dir} | tr '/' '-')

echo; echo "LOADING AND PREPARING INPUTS"

# Load inputs
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh
source /pw/.miniconda3/etc/profile.d/conda.sh
conda activate

python /swift-pw-bin/utils/input_form_resource_wrapper.py
source utils/workflow-libs.sh
source resources/${rlabel}/inputs.sh

batch_header=resources/${rlabel}/batch_header.sh

sshcmd="ssh -o StrictHostKeyChecking=no ${resource_publicIp}"

# FIXME: Improve the tag of the openfoam parameters (openfoam_)
openfoam_args=$(cat resources/${rlabel}/inputs.sh | grep openfoam_ | grep -v resource_ | sed "s|export openfoam_|--|g" | tr '=' ' ')
echo "OpenFOAM args: ${openfoam_args}"

echo; echo "PREPARING KILL SCRIPT TO CLEAN JOB"
sed -i "s|__controller__|${resource_publicIp}|g" kill.sh
sed -i "s|__job_dir__|${job_dir}|g" kill.sh

echo; echo "CHECKING OPENFOAM CASE"
case_exists=$(${sshcmd} "[ -d '${openfoam_case_dir}' ] && echo 'true' || echo 'false'")

if ! [[ "${case_exists}" == "true" ]]; then
    echo "ERROR: Could find OpenFOAM case [${openfoam_case_dir}] on remote host [${resource_publicIp}]"
    echo "Try: ${sshcmd} ls ${openfoam_case_dir}"
    exit 1
fi

echo; echo "PREPARING CONTROLLER NODE"
echo "${sshcmd} mkdir -p ${resource_jobdir}"
${sshcmd} mkdir -p ${resource_jobdir}
if [ -z "${openfoam_load_cmd}" ]; then
    echo "Build singularity container if not present"
    set -x
    cat  bootstrap/openfoam-template.def | sed "s/__openfoam_image__/${openfoam_image}/g" > bootstrap/${openfoam_image}.def
    cat resources/${rlabel}/inputs.sh | grep openfoam_ > bootstrap/bootstrap.sh
    cat bootstrap/bootstrap_template.sh >> bootstrap/bootstrap.sh 
    scp -r bootstrap ${resource_publicIp}:${resource_jobdir}
    ${sshcmd} bash ${resource_jobdir}/bootstrap/bootstrap.sh > resources/${rlabel}/singularity_bootstrap.log 2>&1
    set +x
fi

cases_json_file=${openfoam_case_dir}/cases.json
json_exists=$(${sshcmd} "[ -f '${cases_json_file}' ] && echo 'true' || echo 'false'")
if [[ "${json_exists}" == "true" ]]; then
    echo; echo "CREATING OPENFOAM CASES"
    cases_json=$(${sshcmd} cat ${cases_json_file})
    case_dirs=$(python3 -c "c=${cases_json}; [ print(case['directory']) for ci,case in enumerate(c['cases'])]")
    echo "  Creating run directories:" ${case_dirs}
    python3 -c "import json; c=${cases_json}; print(json.dumps(c, indent=4))"
    scp create_cases.py ${resource_publicIp}:${resource_jobdir}
    # Obtain and format OpenFOAM parameters from workflow input form
    ${sshcmd} python3 ${resource_jobdir}/create_cases.py --cases_json ${cases_json_file} --jobdir ${resource_jobdir} ${openfoam_args}
else
    case_dirs="case"
    echo; echo "Copying OpenFOAM case from [${openfoam_case_dir}] to [${resource_jobdir}/${case_dirs}]"
    ${sshcmd} "cp -r ${openfoam_case_dir} ${resource_jobdir}/${case_dirs}"
fi


echo; echo "CREATING SLURM WRAPPERS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    # Case directory in user container
    mkdir -p ${PWD}/${case_dir}
    submit_job_sh=${PWD}/${case_dir}/submit_job.sh
    chdir=${resource_jobdir}/${case_dir}
    # Create submit script
    cp ${batch_header} ${submit_job_sh}
    if [[ ${jobschedulertype} == "SLURM" ]]; then 
        echo "#SBATCH -o ${chdir}/pw-${job_id}.out" >> ${submit_job_sh}
        echo "#SBATCH -e ${chdir}/pw-${job_id}.out" >> ${submit_job_sh}
    elif [[ ${jobschedulertype} == "PBS" ]]; then
        echo "#PBS -o ${chdir}/pw-${job_id}.out" >> ${submit_job_sh}
        echo "#PBS -e ${chdir}/pw-${job_id}.out" >> ${submit_job_sh}
    fi
    echo "cd ${chdir}"              >> ${submit_job_sh}
    echo "touch case.foam"          >> ${submit_job_sh}
    if [[ "${resource_type}" == "slurmshv2" ]]; then
        echo "bash ${resource_workdir}/pw/.pw/remote.sh &> /tmp/remote-sh-${RANDOM}.out" >> ${submit_job_sh}
    fi
    if [ -z "${openfoam_load_cmd}" ]; then
        bash utils/create_singularity_wrapper.sh ${submit_job_sh} ${case_dir}
        echo "singularity exec -B ${resource_jobdir}/${case_dir}:${resource_jobdir}/${case_dir} ${openfoam_sif_file} /bin/bash ./Allrun" >> ${submit_job_sh}
    else
        echo "${openfoam_load_cmd}" | sed "s|___| |g" | tr ';' '\n' >> ${submit_job_sh}
        echo "/bin/bash ./Allrun"  >> ${submit_job_sh}
    fi
    cat ${submit_job_sh}
    scp ${submit_job_sh} ${resource_publicIp}:${resource_jobdir}/${case_dir}
done


echo; echo "LAUNCHING JOBS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    remote_submit_job_sh=${resource_jobdir}/${case_dir}/submit_job.sh
    echo "  Running:"
    echo "    $sshcmd \"bash --login -c \\"${submit_cmd} ${remote_submit_job_sh}\\"\""
    slurm_job=$($sshcmd "bash --login -c \"${submit_cmd} ${remote_submit_job_sh}\"" | tail -1 | awk -F ' ' '{print $4}')
    if [ -z "${slurm_job}" ]; then
        echo "    ERROR submitting job - exiting the workflow"
        exit 1
    fi
    echo "    Submitted job ${slurm_job}"
    echo ${slurm_job} > ${PWD}/${case_dir}/slurm_job.submitted
done


echo; echo "CHECKING JOBS STATUS"
while true; do
    date
    submitted_jobs=$(find . -name slurm_job.submitted)

    if [ -z "${submitted_jobs}" ]; then
        if [[ "${FAILED}" == "true" ]]; then
            echo "ERROR: Jobs [${FAILED_JOBS}] failed"
            exit 1
        fi
        echo "  All jobs are completed. Please check job logs in directories [${case_dirs}] and results"
        exit 0
    fi

    for sj in ${submitted_jobs}; do
        jobid=$(cat ${sj})
        get_job_status
        if [[ $? -eq 1 ]]; then
            # Job completed
            mv ${sj} ${sj}.completed
            sj_status=$($sshcmd sacct -j ${slurm_job}  --format=state | tail -n1 | tr -d ' ')
            case_dir=$(dirname ${sj} | sed "s|${PWD}/||g")
            scp ${resource_publicIp}:${resource_jobdir}/${case_dir}/pw-${job_id}.out ${case_dir}
        elif [[ $? -eq 2 ]]; then
            # Job failed
            FAILED=true
            FAILED_JOBS="${slurm_job}, ${FAILED_JOBS}"
        fi
    done
    sleep 60
done
