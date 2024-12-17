#!/bin/bash

# Use the resource wrapper
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh
source /pw/.miniconda3/etc/profile.d/conda.sh
conda activate

if [ -z "${workflow_utils_branch}" ]; then
    # If empty, clone the main default branch
    git clone https://github.com/parallelworks/workflow-utils.git
else
    # If not empty, clone the specified branch
    git clone -b "$workflow_utils_branch" https://github.com/parallelworks/workflow-utils.git
fi

python3 ./workflow-utils/input_form_resource_wrapper.py 

# Load useful functions
source workflow-libs.sh

# Load resource inputs
source resources/ofhost/inputs.sh
export sshcmd="ssh -o StrictHostKeyChecking=no ${resource_publicIp}"

# Run job on remote resource
cluster_rsync_exec
