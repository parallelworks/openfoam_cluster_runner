#!/bin/bash
sif_file=$1
def_file=$2

if [ -f "${sif_file}" ]; then
    echo "Singularuty file ${sif_file} already exists"
else
    echo "Building singularity file"
    mkdir -p $(dirname ${sif_file})
    # Sometimes root cant find singularity :s
    sudo $(which singularity) build ${sif_file} ${def_file}
fi
