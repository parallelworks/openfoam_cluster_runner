# OpenFOAM Runner

Runs an OpenFOAM parameter sweep in a slurm cluster using a singularity container. The cases are templated using a JSON file, see `cyclone-template/cyclone-cases.json`. The workflow uses the templated OpenFOAM case directory (see `cyclone-template`) to create a new run directory for each case, as specified in the JSON file. Slurm jobs are submitted for each case in Parallel. Workflow exits when all cases are completed.
