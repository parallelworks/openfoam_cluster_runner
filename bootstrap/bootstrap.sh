#!/bin/bash
bdir=$(dirname $0)
sif_file=__sif_file__
of_image=__of_image__

module load singularity

# Install singularity if it does not exist:
if [ -z $(which singularity) ]; then
    echo "Installing singularity"
    bash ${bdir}/install_singularity.sh
fi

# Build singularity container if sif_file is not present
bash ${bdir}/build_singularity.sh ${sif_file} ${bdir}/${of_image}.def
