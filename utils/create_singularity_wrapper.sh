#!/bin/bash
session_sh=$1
case_dir=$2

cat >> ${session_sh} <<HERE

{
    module load singularity
} || {
    echo "Failed to run: module load singularity"
}

# Install singularity if it does not exist:
if [ -z \$(which singularity) ]; then
    echo "Installing singularity"
    bash ${chdir}/bootstrap/install_singularity.sh
fi

# To be able to open any case in Paraview
# Be sure to go select properties -> desconstructed / reconstructed in paraview

# FIX new singularity error on the cloud:
{
    sudo -n sh -c 'echo user.max_user_namespaces=15000 >/etc/sysctl.d/90-max_user_namespaces.conf'
    sudo -n sysctl -p /etc/sysctl.d/90-max_user_namespaces.conf
} || {
    echo 'Failed to increase the number of namespaces'
}

HERE
