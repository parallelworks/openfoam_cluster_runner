#!/bin/bash

# These are utility bash functions intended to make workflow building easier. They can
# be imported by any bash workflow using source /swift-pw-bin/utils/workflow-libs.sh
# All these functions run as part of the workflow inside the user workspace.


cluster_rsync_exec() {
    # DESCRIPTION:
    # 1. Looks for every script named cluster_rsync_exec.sh under the ./resources directory
    # 1. Copies the ./resources/<resource-label>/ directory to the job directory in the remote resource
    # 2. Executes the script ./resources/<resource-label>/cluster_rsync_exec.sh in the remote resource
    # PREREQUISITES:
    # Run python3 /swift-pw-bin/utils/input_form_resource_wrapper.py before this function
    for path_to_rsync_exec_sh in $(find resources -name cluster_rsync_exec.sh); do
        chmod +x ${path_to_rsync_exec_sh}
        resource_dir=$(dirname ${path_to_rsync_exec_sh})
        resource_label=$(basename ${resource_dir})

        # Load resource inputs
        source ${resource_dir}/inputs.sh

        echo; echo "Running ${path_to_rsync_exec_sh} in ${resource_publicIp}"

        # Copy the file containing this function to the resource directory
        cp ${BASH_SOURCE[0]} ${resource_dir}
        
        # Rsync resource directory in user space to job directory in the resource
        origin=${resource_dir}/
        destination=${resource_publicIp}:${resource_jobdir}/${resource_label}/
        echo "rsync -avzq --rsync-path="mkdir -p ${resource_jobdir} && rsync " ${origin} ${destination}"
        rsync -avzq --rsync-path="mkdir -p ${resource_jobdir} && rsync " ${origin} ${destination}
        
        # Execute the script
        echo "ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/cluster_rsync_exec.sh"
        ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/cluster_rsync_exec.sh
    done
}



get_job_status(){
    # Runs inside wait_job and wait_job_timeout
    job_status=$($sshcmd ${status_cmd} | awk -v id="${jobid}" '$1 == id {print $5}')
    if [[ ${jobschedulertype} == "SLURM" ]]; then
        # If job status is empty job is no longer running
        if [ -z "${job_status}" ]; then
            job_status=$($sshcmd sacct -j ${jobid}  --format=state | tail -n1)
            echo "    Job ${jobid} exited with status ${job_status}"
            if [[ "${job_status}" == *"FAILED"* ]]; then
                echo "ERROR: SLURM job [${slurm_job}] failed"
                return 2
            else
                return 1
            fi
        fi
    elif [[ ${jobschedulertype} == "PBS" ]]; then
        if [[ "${job_status}" == "C" ]]; then
            echo "Job ${jobid} exited with status C"
            return 1
        fi
        if [ -z "${job_status}" ]; then
            echo "Job ${jobid} exited"
            return 1
        fi
    fi
    return 0
}

wait_job() {
    # DESCRIPTION:
    # Given a SLURM or PBS job id it waits for the job to finish.
    # REQUIRED ENVIRONMENT VARIABLES
    # 1. jobid: SLURM or PBS job id
    # 2. jobschedulertype: Scheduler type of the resource running the job. Must be SLURM or PBS.
    # 3. sshcmd: Command to ssh into the remote resource, e.g.: ssh -o StrictHostKeyChecking=no <user>@<external-ip>
    while true; do
        # squeue won't give you status of jobs that are not running or waiting to run
        # qstat returns the status of all recent jobs
        get_job_status
        if [[ $? -eq 1 ]]; then
            break
        elif [[ $? -eq 2 ]]; then
            exit 1
        fi
        echo "    Job ${jobid} status: ${job_status}"
        sleep 5
    done
}


wait_job_timeout() {
    # DESCRIPTION:
    # Given a SLURM or PBS job id it waits for the job to finish.
    # REQUIRED ENVIRONMENT VARIABLES
    # 1. max_time: Maximum time before timeout in seconds
    # 2. jobid: SLURM or PBS job id
    # 3. jobschedulertype: Scheduler type of the resource running the job. Must be SLURM or PBS.
    # 4. sshcmd: Command to ssh into the remote resource, e.g.: ssh -o StrictHostKeyChecking=no <user>@<external-ip>
    end_time=$((SECONDS + max_time))
    while [[ $SECONDS -lt $end_time ]]; do
        get_job_status
        if [[ $? -eq 1 ]]; then
            exit 0
        elif [[ $? -eq 2 ]]; then
            # Break to resubmit to another resource
            # exit 1 to fail
            break
        fi
        echo "    Job ${jobid} status: ${job_status}"
        sleep 5
    done
}


install_miniconda() {
    install_dir=$1
    echo "Installing Miniconda3-py39_4.9.2"
    conda_repo="https://repo.anaconda.com/miniconda/Miniconda3-py39_4.9.2-Linux-x86_64.sh"
    ID=$(date +%s)-${RANDOM} # This script may run at the same time!
    nohup wget ${conda_repo} -O /tmp/miniconda-${ID}.sh 2>&1 > /tmp/miniconda_wget-${ID}.out
    rm -rf ${install_dir}
    mkdir -p $(dirname ${install_dir})
    nohup bash /tmp/miniconda-${ID}.sh -b -p ${install_dir} 2>&1 > /tmp/miniconda_sh-${ID}.out
}

create_conda_env_from_yaml() {
    CONDA_DIR=$1
    CONDA_ENV=$2
    CONDA_YAML=$3
    CONDA_SH="${CONDA_DIR}/etc/profile.d/conda.sh"
    # conda env export
    # Remove line starting with name, prefix and remove empty lines
    sed -i -e 's/name.*$//' -e 's/prefix.*$//' -e '/^$/d' ${CONDA_YAML}    
    
    if [ ! -d "${CONDA_DIR}" ]; then
        echo "Conda directory <${CONDA_DIR}> not found. Installing conda..."
        install_miniconda ${CONDA_DIR}
    fi
    
    echo "Sourcing Conda SH <${CONDA_SH}>"
    source ${CONDA_SH}
    echo "Activating Conda Environment <${CONDA_ENV}>"
    {
        conda activate ${CONDA_ENV}
    } || {
        echo "Conda environment <${CONDA_ENV}> not found. Installing conda environment from YAML file <${CONDA_YAML}>"
        conda env update -n ${CONDA_ENV} -q -f ${CONDA_YAML} #--prune
        {
            echo "Activating Conda Environment <${CONDA_ENV}> again"
            conda activate ${CONDA_ENV}
        } || {
            echo "ERROR: Conda environment <${CONDA_ENV}> not found. Exiting workflow"
            exit 1
        }
    }
}
