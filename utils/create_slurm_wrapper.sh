#!/bin/bash
session_sh=$1
case_dir=$2
echo "#!/bin/bash" > ${session_sh}
# SET SLURM DEFAULT VALUES:
if ! [ -z ${partition} ] && ! [[ "${partition}" == "default" ]]; then
    echo "#SBATCH --partition=${partition}" >> ${session_sh}
fi

if ! [ -z ${account} ] && ! [[ "${account}" == "default" ]]; then
    echo "#SBATCH --account=${account}" >> ${session_sh}
fi

if ! [ -z ${walltime} ] && ! [[ "${walltime}" == "default" ]]; then
    echo "#SBATCH --time=${walltime}" >> ${session_sh}
fi

if ! [ -z ${chdir} ] && ! [[ "${chdir}" == "default" ]]; then
    echo "#SBATCH --chdir=${chdir}/${case_dir}" >> ${session_sh}
fi

if [ -z ${numnodes} ]; then
    echo "#SBATCH --nodes=1" >> ${session_sh}
else
    echo "#SBATCH --nodes=${numnodes}" >> ${session_sh}
fi

if [[ "${exclusive}" == "True" ]]; then
    echo "#SBATCH --exclusive" >> ${session_sh}
fi

if ! [ -z ${cpus_per_task} ]; then
    echo "#SBATCH --cpus-per-task=${cpus_per_task}" >> ${session_sh}
fi

echo "#SBATCH --job-name=pw-${job_number}" >> ${session_sh}
echo "#SBATCH --output=pw-${job_number}.out" >> ${session_sh}
echo >> ${session_sh}

cat >> ${session_sh} <<HERE

# To connect the worker:
if [ -f "${poolworkdir}/pw/remote.sh" ]; then
    echo "Running  ${remote_sh}"
    ${remote_sh}
fi

# Install singularity if it does not exist:
if [ -z $(which singularity) ]; then
    echo "Installing singularity"
    bash ${chdir}/bootstrap/install_singularity.sh
fi

# To be able to open any case in Paraview
# Be sure to go select properties -> desconstructed / reconstructed in paraview
touch case.foam

HERE
