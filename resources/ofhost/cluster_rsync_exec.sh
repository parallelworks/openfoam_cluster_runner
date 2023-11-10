#!/bin/bash
jobdir=$(dirname $0)
cd ${jobdir}

# Initialize cancel script
echo '#!/bin/bash' > cancel.sh
chmod +x cancel.sh


source inputs.sh
source workflow-libs.sh


echo; echo "CHECKING OPENFOAM CASE"
if ! [ -d ${openfoam_case_dir} ]; then
    echo "ERROR: Could find OpenFOAM case [${openfoam_case_dir}] on remote host [${resource_publicIp}]"
    echo "Try: ${sshcmd} ls ${openfoam_case_dir}"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not in the PATH. Exiting workflow."
    exit 1
fi

echo; echo "PREPARING CONTROLLER NODE"
if [ -z "${openfoam_load_cmd}" ]; then
    echo "Build singularity container if not present"
    set -x
    cat bootstrap/openfoam-template.def | sed "s/__openfoam_image__/${openfoam_image}/g" > bootstrap/${openfoam_image}.def
    cat inputs.sh | grep openfoam_ > bootstrap/bootstrap.sh
    cat bootstrap/bootstrap_template.sh >> bootstrap/bootstrap.sh 
    bash bootstrap/bootstrap.sh > singularity_bootstrap.log 2>&1
    set +x
fi


cases_json_file=${openfoam_case_dir}/cases.json

if [ -f ${cases_json_file} ]; then
    echo; echo "CREATING OPENFOAM CASES"
    cases_json=$(cat ${cases_json_file})
    case_dirs=$(python3 -c "c=${cases_json}; [ print(case['directory']) for ci,case in enumerate(c['cases'])]")
    echo "  Creating run directories:" ${case_dirs}
    python3 -c "import json; c=${cases_json}; print(json.dumps(c, indent=4))"
    # create_cases.py reads inputs.json
    python3 create_cases.py
    
else
    case_dirs="case"
    echo; echo "Copying OpenFOAM case from [${openfoam_case_dir}] to [${resource_jobdir}/${case_dirs}]"
    ${sshcmd} "cp -r ${openfoam_case_dir} ${resource_jobdir}/${case_dirs}"
fi


echo; echo "CREATING SLURM WRAPPERS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    # Case directory in user container
    mkdir -p ${resource_jobdir}/${case_dir}
    submit_job_sh=${resource_jobdir}/${case_dir}/submit_job.sh
    chdir=${resource_jobdir}/${case_dir}
    # Create submit script
    cp batch_header.sh ${submit_job_sh}
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
        # FIXME: Support multinode singularity
        cat singularity_wrapper.sh >> ${submit_job_sh}
        echo "singularity exec -B ${resource_jobdir}/${case_dir}:${resource_jobdir}/${case_dir} ${openfoam_sif_file} /bin/bash ./Allrun" >> ${submit_job_sh}
    else
        echo "${openfoam_load_cmd}" | sed "s|___| |g" | tr ';' '\n' >> ${submit_job_sh}
        echo "/bin/bash ./Allrun"  >> ${submit_job_sh}
    fi
    cat ${submit_job_sh}
done

echo; echo "LAUNCHING JOBS"
for case_dir in ${case_dirs}; do
    echo "  Case directory: ${case_dir}"
    submit_job_sh=${resource_jobdir}/${case_dir}/submit_job.sh
    echo "  Running:"
    echo "  bash ${submit_cmd} ${submit_job_sh}"
    if [[ ${jobschedulertype} == "SLURM" ]]; then 
        batch_job=$(${submit_cmd} ${submit_job_sh} | tail -1 | awk -F ' ' '{print $4}')
    elif [[ ${jobschedulertype} == "PBS" ]]; then
        batch_job=$(${submit_cmd} ${submit_job_sh} | tail -1)
    fi
    if [ -z "${batch_job}" ]; then
        echo "    ERROR submitting job - exiting the workflow"
        exit 1
    fi
    # Required to cancel the job from PW:
    echo "${cancel_cmd} ${batch_job}" >> cancel.sh
    echo "    Submitted job ${batch_job}"
    # Only one batch job per case dir
    echo ${batch_job} > ${resource_jobdir}/${case_dir}/batch_job.submitted
done




echo; echo "CHECKING JOBS STATUS"
while true; do
    date
    submitted_jobs=$(find ${resource_jobdir} -name batch_job.submitted)

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
        job_status_ec=$?
        echo "  Status of job ${jobid} is ${job_status}"
        if [[ ${job_status_ec} -eq 1 ]]; then
            # Job completed
            mv ${sj} ${sj}.completed
        elif [[ ${job_status_ec} -eq 2 ]]; then
            # Job failed
            FAILED=true
            FAILED_JOBS="${jobid}, ${FAILED_JOBS}"
        fi
    done
    sleep 60
done
