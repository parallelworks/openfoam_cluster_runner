#!/bin/bash
date
# Resource label
export rlabel=ofhost
export job_dir=$(pwd | rev | cut -d'/' -f1-2 | rev)
export job_id=$(echo ${job_dir} | tr '/' '-')

echo; echo "LOADING AND PREPARING INPUTS"
# Overwrite input form and resource definition page defaults
sed -i "s|__USER__|${PW_USER}|g" inputs.sh
sed -i "s|__USER__|${PW_USER}|g" inputs.json

# Load inputs
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh
source /pw/.miniconda3/etc/profile.d/conda.sh
conda activate

python /swift-pw-bin/utils/input_form_resource_wrapper.py
source inputs.sh
source resources/${rlabel}/inputs.sh

batch_header=resources/${rlabel}/batch_header.sh

sshcmd="ssh -o StrictHostKeyChecking=no ${resource_publicIp}"

openfoam_args=$(cat inputs.sh | grep openfoam_ | sed "s|export openfoam_|--|g" | tr '=' ' ')
echo "OpenFOAM args: ${openfoam_args}"

export remote_job_dir=${workdir}/${job_dir}

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
echo "${sshcmd} mkdir -p ${remote_job_dir}"
${sshcmd} mkdir -p ${remote_job_dir}
if [ -z "${openfoam_load_cmd}" ]; then
    # - Build singularity container if not present
    cat  bootstrap/openfoam-template.def | sed "s/__of_image__/${openfoam_sing_image}/g" > bootstrap/${openfoam_sing_image}.def
    replace_templated_inputs bootstrap/bootstrap.sh ${wfargs}
    scp -r bootstrap ${resource_publicIp}:${remote_job_dir}
    ${sshcmd} bash ${remote_job_dir}/bootstrap/bootstrap.sh > resources/${rlabel}/singularity_bootstrap.log 2>&1
fi

cases_json_file=${openfoam_case_dir}/cases.json
json_exists=$(${sshcmd} "[ -f '${cases_json_file}' ] && echo 'true' || echo 'false'")
if [[ "${json_exists}" == "true" ]]; then
    echo; echo "CREATING OPENFOAM CASES"
    cases_json=$(${sshcmd} cat ${cases_json_file})
    case_dirs=$(python3 -c "c=${cases_json}; [ print(case['directory']) for ci,case in enumerate(c['cases'])]")
    echo "  Creating run directories:" ${case_dirs}
    python3 -c "import json; c=${cases_json}; print(json.dumps(c, indent=4))"
    scp create_cases.py ${resource_publicIp}:${remote_job_dir}
    # Obtain and format OpenFOAM parameters from workflow input form
    ${sshcmd} python3 ${remote_job_dir}/create_cases.py --cases_json ${cases_json_file} --jobdir ${remote_job_dir} ${openfoam_args}
else
    case_dirs="case"
    echo; echo "Copying OpenFOAM case from [${openfoam_case_dir}] to [${remote_job_dir}/${case_dirs}]"
    ${sshcmd} "cp -r ${openfoam_case_dir} ${remote_job_dir}/${case_dirs}"
fi


echo; echo "CREATING SLURM WRAPPERS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    # Case directory in user container
    mkdir -p ${PWD}/${case_dir}
    sbatch_sh=${PWD}/${case_dir}/sbatch.sh
    chdir=${remote_job_dir}/${case_dir}
    # Create submit script
    cp ${batch_header} ${sbatch_sh}
    echo "#SBATCH -o ${chdir}/pw-${job_id}.out" >> ${sbatch_sh}
    echo "#SBATCH -e ${chdir}/pw-${job_id}.out" >> ${sbatch_sh}
    echo "#SBATCH --chdir=${chdir}" >> ${sbatch_sh}
    echo "cd ${chdir}"              >> ${sbatch_sh}
    echo "touch case.foam"          >> ${sbatch_sh}
    if [[ "${resource_type}" == "slurmshv2" ]]; then
        echo "bash ${resource_workdir}/pw/.pw/remote.sh" >> ${sbatch_sh}
    fi
    if [ -z "${openfoam_load_cmd}" ]; then
        bash utils/create_singularity_wrapper.sh ${sbatch_sh} ${case_dir}
        echo "singularity exec -B ${remote_job_dir}/${case_dir}:${remote_job_dir}/${case_dir} ${sif_file} /bin/bash ./Allrun" >> ${sbatch_sh}
    else
        echo "${openfoam_load_cmd}" | sed "s|___| |g" | tr ';' '\n' >> ${sbatch_sh}
        echo "/bin/bash ./Allrun"  >> ${sbatch_sh}
    fi
    cat ${sbatch_sh}
    scp ${sbatch_sh} ${resource_publicIp}:${remote_job_dir}/${case_dir}
done


echo; echo "LAUNCHING JOBS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    remote_sbatch_sh=${remote_job_dir}/${case_dir}/sbatch.sh
    echo "  Running:"
    echo "    $sshcmd \"bash --login -c \\"sbatch ${remote_sbatch_sh}\\"\""
    slurm_job=$($sshcmd "bash --login -c \"sbatch ${remote_sbatch_sh}\"" | tail -1 | awk -F ' ' '{print $4}')
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
        slurm_job=$(cat ${sj})
        sj_status=$($sshcmd squeue -j ${slurm_job} | tail -n+2 | awk '{print $5}')
        if [ -z "${sj_status}" ]; then
            mv ${sj} ${sj}.completed
            sj_status=$($sshcmd sacct -j ${slurm_job}  --format=state | tail -n1 | tr -d ' ')
            case_dir=$(dirname ${sj} | sed "s|${PWD}/||g")
            scp ${resource_publicIp}:${remote_job_dir}/${case_dir}/pw-${job_id}.out ${case_dir}
        fi
        echo "  Slurm job ${slurm_job} status is ${sj_status}"
        if [[ "${sj_status}" == "FAILED" ]]; then
            FAILED=true
            FAILED_JOBS="${slurm_job}, ${FAILED_JOBS}"
        fi
    done
    sleep 60
done