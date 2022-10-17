#!/bin/bash
bdir=$(dirname $0)
sif_file=__sif_file__
of_image=__of_image__

# Build singularity container if sif_file is not present
bash ${bdir}/build_singularity.sh ${sif_file} ${bdir}/${of_image}.def

# Create OpenFOAM cases:
python ${bdir}/create_cases.py cases.json