#!/bin/bash
bdir=$(dirname $0)
sif_file=__sif_file__
def_file=__def_file__

# Build singularity container if sif_file is not present
bash ${bdir}/build_singularity.sh ${sif_file} ${bdir}/${def_file}

# Create OpenFOAM cases:
python ${bdir}/create_cases.py cases.json