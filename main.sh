#!/bin/bash
set -x
source utils/lib.sh
export job_number=$(basename ${PWD})

echo
echo "JOB NUMBER:  ${job_number}"
echo "USER:        ${PW_USER}"
echo "DATE:        $(date)"
echo

wfargs="$(echo $@ | sed "s|__JOB_NUMBER__|${job_number}|g" | sed "s|__USER__|${PW_USER}|g") --job_number ${job_number}"
parseArgs ${wfargs}

# Sets poolname, controller, pooltype and poolworkdir
exportResourceInfo
echo "Resource name:    ${poolname}"
echo "Controller:       ${controller}"
echo "Resource type:    ${pooltype}"
echo "Resource workdir: ${poolworkdir}"
echo

wfargs="$(echo ${wfargs} | sed "s|__RESOURCE_WORKDIR__|${poolworkdir}|g")"
wfargs="$(echo ${wfargs} | sed "s|--_pw_controller pw.conf|--_pw_controller ${controller}|g")"

echo "$0 $wfargs"; echo
parseArgs ${wfargs}

echo; echo "CREATING GENERAL SLURM HEADER"
getBatchScriptHeader ofhost > slurm_directives.sh
chmod +x slurm_directives.sh
cat slurm_directives.sh

echo; echo "PREPARING KILL SCRIPT TO CLEAN JOB"
sed -i "s|__controller__|${controller}|g" kill.sh
sed -i "s|__job_number__|${job_number}|g" kill.sh

sshcmd="ssh -o StrictHostKeyChecking=no ${controller}"

echo; echo "CHECKING OPENFOAM CASE"
case_exists=$(${sshcmd} "[ -d '${openfoam_case}' ] && echo 'true' || echo 'false'")

if ! [[ "${case_exists}" == "true" ]]; then
    echo "ERROR: Could find OpenFOAM case <${openfoam_case}> on remote host <${controller}>"
    echo "Try: ${sshcmd} ls ${openfoam_case}"
    exit 1
fi

echo; echo "PREPARING CONTROLLER NODE:"
${sshcmd} mkdir -p ${jobdir}
if [ -z "${load_openfoam}" ]; then
    # - Build singularity container if not present
    cat  bootstrap/openfoam-template.def | sed "s/__of_image__/${of_image}/g" > bootstrap/${of_image}.def
    replace_templated_inputs bootstrap/bootstrap.sh ${wfargs}
    scp -r bootstrap ${controller}:${jobdir}
    ${sshcmd} bash ${jobdir}/bootstrap/bootstrap.sh > bootstrap.log 2>&1
fi

cases_json_file=${openfoam_case}/cases.json
json_exists=$(${sshcmd} "[ -f '${cases_json_file}' ] && echo 'true' || echo 'false'")
if [[ "${json_exists}" == "true" ]]; then
    echo; echo "CREATING OPENFOAM CASES"
    cases_json=$(${sshcmd} cat ${cases_json_file})
    case_dirs=$(python3 -c "c=${cases_json}; [ print(case['directory']) for ci,case in enumerate(c['cases'])]")
    echo "  Creating run directories:" ${case_dirs}
    python3 -c "import json; c=${cases_json}; print(json.dumps(c, indent=4))"
    scp create_cases.py ${controller}:${jobdir}
    # Obtain and format OpenFOAM parameters from workflow input form
    formparams=$(env | grep ofparam_ | sed "s|ofparam_|--|g" | sed "s|=| |g")
    ${sshcmd} python3 ${jobdir}/create_cases.py --cases_json ${cases_json_file} --jobdir ${jobdir} ${formparams}
else
    case_dirs="case"
    echo; echo "Copying OpenFOAM case from <${openfoam_case}> to <${case_dirs}>"
    ${sshcmd} "cp -r ${openfoam_case} ${case_dirs}"
fi


echo; echo "CREATING SLURM WRAPPERS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    # Case directory in user container
    mkdir -p ${PWD}/${case_dir}
    sbatch_sh=${PWD}/${case_dir}/sbatch.sh
    chdir=${jobdir}/${case_dir}
    # Create submit script
    cp slurm_directives.sh ${sbatch_sh}
    echo "#SBATCH -o ${chdir}/pw-${job_number}.out" >> ${sbatch_sh}
    echo "#SBATCH -e ${chdir}/pw-${job_number}.out" >> ${sbatch_sh}
    echo "#SBATCH --chdir=${chdir}" >> ${sbatch_sh}
    echo "cd ${chdir}"              >> ${sbatch_sh}
    echo "touch case.foam"          >> ${sbatch_sh}
    if [[ "${pooltype}" == "slurmshv2" ]]; then
        echo "    bash ${poolworkdir}/pw/.pw/remote.sh" >> ${sbatch_sh}
    fi
    if [ -z "${load_openfoam}" ]; then
        bash utils/create_singularity_wrapper.sh ${sbatch_sh} ${case_dir}
        echo "singularity exec -B ${jobdir}/${case_dir}:${jobdir}/${case_dir} ${sif_file} /bin/bash ./Allrun" >> ${sbatch_sh}
    else
        echo "${load_openfoam}" | sed "s|___| |g" | tr ';' '\n' >> ${sbatch_sh}
        echo "/bin/bash ./Allrun"  >> ${sbatch_sh}
    fi
    cat ${sbatch_sh}
    scp ${sbatch_sh} ${controller}:${jobdir}/${case_dir}
done


echo; echo "LAUNCHING JOBS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    remote_sbatch_sh=${jobdir}/${case_dir}/sbatch.sh
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
            echo "ERROR: Jobs <${FAILED_JOBS}> failed"
            exit 1
        fi
        echo "  All jobs are completed. Please check job logs in directories <" ${case_dirs} "> and results"
        exit 0
    fi

    for sj in ${submitted_jobs}; do
        slurm_job=$(cat ${sj})
        sj_status=$($sshcmd squeue -j ${slurm_job} | tail -n+2 | awk '{print $5}')
        if [ -z "${sj_status}" ]; then
            mv ${sj} ${sj}.completed
            sj_status=$($sshcmd sacct -j ${slurm_job}  --format=state | tail -n1 | tr -d ' ')
            case_dir=$(dirname ${sj} | sed "s|${PWD}/||g")
            scp ${controller}: ${controller}:${jobdir}/${case_dir}/pw-${job_number}.out ${case_dir}
        fi
        echo "  Slurm job ${slurm_job} status is ${sj_status}"
        if [[ "${sj_status}" == "FAILED" ]]; then
            FAILED=true
            FAILED_JOBS="${slurm_job}, ${FAILED_JOBS}"
        fi
    done
    sleep 60
done