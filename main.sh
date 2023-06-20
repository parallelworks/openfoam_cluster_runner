#!/bin/bash
set -x
source utils/lib.sh
export job_number=$(basename ${PWD})

echo
echo "JOB NUMBER:  ${job_number}"
echo "USER:        ${PW_USER}"
echo "DATE:        $(date)"
echo

wfargs="$(echo $@ | sed "s|__job_number__|${job_number}|g" | sed "s|__USER__|${PW_USER}|g") --job_number ${job_number}"
parseArgs ${wfargs}

# Sets poolname, controller, pooltype and poolworkdir
exportResourceInfo
echo "Pool name:    ${poolname}"
echo "controller:   ${controller}"
echo "Pool type:    ${pooltype}"
echo "Pool workdir: ${poolworkdir}"
echo

wfargs="$(echo ${wfargs} | sed "s|__poolworkdir__|${poolworkdir}|g")"
wfargs="$(echo ${wfargs} | sed "s|--controller pw.conf|--controller ${controller}|g")"

echo "$0 $wfargs"; echo
parseArgs ${wfargs}

echo; echo "PREPARING KILL SCRIPT TO CLEAN JOB"
replace_templated_inputs kill.sh ${wfargs}

sshcmd="ssh -o StrictHostKeyChecking=no ${controller}"

echo; echo "READING OPENFOAM CASES"
cases_json=$(${sshcmd} cat ${cases_json_file})
if [ -z "${cases_json}" ]; then
    echo "WARNING: Could not read file ${cases_json_file}"
    echo "         Try: ${sshcmd} cat ${cases_json_file}"
    echo "         Copying sample templated case"
    remote_cyclone_dir="$(dirname ${cases_json_file})/"
    ${sshcmd} "mkdir -p ${remote_cyclone_dir}"
    echo "rsync -avzq cyclone-template/ ${controller}:${remote_cyclone_dir}"
    rsync -avzq cyclone-template/ ${controller}:${remote_cyclone_dir}
    cases_json=$(${sshcmd} cat ${cases_json_file})
    if [ -z "${cases_json}" ]; then
        echo "ERROR: Could not read file ${cases_json_file}"
        echo "Try: ${sshcmd} cat ${cases_json_file}"
        exit 1
    fi
fi

if [ -z "${load_openfoam}" ]; then
    echo; echo "PREPARING CONTROLLER NODE:"
    # - Build singularity container if not present
    cat  bootstrap/openfoam-template.def | sed "s/__of_image__/${of_image}/g" > bootstrap/${of_image}.def
    replace_templated_inputs bootstrap/bootstrap.sh ${wfargs}
    ${sshcmd} mkdir -p ${chdir}
    scp -r bootstrap ${controller}:${chdir}
    ${sshcmd} bash ${chdir}/bootstrap/bootstrap.sh > bootstrap.log 2>&1
fi

echo; echo "CREATING OPENFOAM CASES"
case_dirs=$(python3 -c "c=${cases_json}; [ print(case['directory']) for ci,case in enumerate(c['cases'])]")
echo "  Creating run directories:" ${case_dirs}
python3 -c "import json; c=${cases_json}; print(json.dumps(c, indent=4))"
scp create_cases.py ${controller}:${chdir}
${sshcmd} python3 ${chdir}/create_cases.py ${cases_json_file} ${chdir}

echo; echo "CREATING SLURM WRAPPERS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    # Case directory in user container
    mkdir -p ${PWD}/${case_dir}
    sbatch_sh=${PWD}/${case_dir}/sbatch.sh
    bash utils/create_slurm_wrapper.sh ${sbatch_sh} ${case_dir}
    if [ -z "${load_openfoam}" ]; then
        bash utils/create_singularity_wrapper.sh ${sbatch_sh} ${case_dir}
        echo "singularity exec -B ${chdir}/${case_dir}:${chdir}/${case_dir} ${sif_file} /bin/bash ./Allrun" >> ${sbatch_sh}
    else
        echo ${load_openfoam} | sed "s|___| |g" >> ${sbatch_sh}
    fi
    cat ${sbatch_sh}
    scp ${sbatch_sh} ${controller}:${chdir}/${case_dir}
done


echo; echo "LAUNCHING JOBS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    remote_sbatch_sh=${chdir}/${case_dir}/sbatch.sh
    echo "  Running:"
    echo "    $sshcmd sbatch ${remote_sbatch_sh}"
    slurm_job=$($sshcmd sbatch ${remote_sbatch_sh} | tail -1 | awk -F ' ' '{print $4}')
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
        echo "  All jobs are completed. Please check job logs in directories <" ${case_dirs} "> and results"
        exit 0
    fi

    for sj in ${submitted_jobs}; do
        slurm_job=$(cat ${sj})
        echo "  Slurm job ID:     ${slurm_job}"
        sj_status=$($sshcmd squeue -j ${slurm_job} | tail -n+2 | awk '{print $5}')
        echo "  Slurm job status: ${sj_status}"
        if [ -z "${sj_status}" ]; then
            mv ${sj} ${sj}.completed
            case_dir=$(dirname ${sj} | sed "s|${PWD}/||g")
            scp ${controller}: ${controller}:${chdir}/${case_dir}/pw-${job_number}.out ${case_dir}
        fi
    done
    sleep 60
done
