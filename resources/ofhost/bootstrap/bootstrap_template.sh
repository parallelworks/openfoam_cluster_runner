
bdir=$(dirname $0)


# Install singularity if it does not exist:
if [ -z $(which singularity) ]; then
    echo "Installing singularity"
    bash ${bdir}/install_singularity.sh
fi

# Build singularity container if openfoam_sif_file is not present
bash ${bdir}/build_singularity.sh ${openfoam_sif_file} ${bdir}/${openfoam_image}.def
