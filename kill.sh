#!/bin/bash
sshcmd="ssh -o StrictHostKeyChecking=no __controller__"
echo; echo "KILLING JOB"
date
submitted_jobs=$(find . -name slurm_job.submitted)
if [ -z "${submitted_jobs}" ]; then
    echo "  All jobs are completed"
    exit 0
fi

for sj in ${submitted_jobs}; do
    slurm_job=$(cat ${sj})
    echo "  Cancelling slurm job:     ${slurm_job}"
    $sshcmd scancel ${slurm_job}
    if [ -z "${sj_status}" ]; then
        mv ${sj} ${sj}.killed
    fi
done
