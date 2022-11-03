# OpenFOAM Runner

Runs an OpenFOAM parameter sweep in a slurm cluster using a singularity container. The workflow requires an OpenFOAM case directory with templated input parameters and a JSON file defining the parameter value replacements for each case.

### 1. Workflow:

The workflow performs the following tasks:

1. Prepares the controller node: Installs singularity if it is not installed and builds the singularity container if no container exists in the specified path (see input form parameters > singularity container).
2. Creates the OpenFOAM cases as defined in the case definition JSON file.
3. Creates the slurm sbatch scripts using the slurm configuration parameters of the input form and the `Allrun` bash script in the templated OpenFOAM directory
4. Submits all the cases to the queue in parallel
5. Streams the output from the remote job directory to the job directory in the user's account (`/pw/jobs/<job-number>/<case directory>`)
6. Waits for the jobs to run

### 2. Templated OpenFOAM Directory:

The templated OpenFOAM directory must be located in a shared directory of the slurm cluster. To ilustrate the process of preparing the OpenFOAM case directory the `cyclone-template` sample is provided in this repository. This sample corresponds to a templated version of the official cyclone OpenFOAM tutorial.

#### 2.1 Templated Files:

The following files have been edited to replace the default values by placeholders: `system/decomposeParDict`, `system/blockMeshDict` and `0/U.air`. For example, note that the `numberOfSubdomains` parameter in the `system/decomposeParDict` file below has been changed from `4` to `__numberOfSubdomains__` and the `n` parameter has been changed from `(2 2 1)` to `(__nx_ny_nz__)`:

```/*--------------------------------*- C++ -*----------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Version:  9
     \\/     M anipulation  |
\*---------------------------------------------------------------------------*/
FoamFile
{
    format      ascii;
    class       dictionary;
    location    "system";
    object      decomposeParDict;
}
// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

numberOfSubdomains __numberOfSubdomains__;

method          simple;

simpleCoeffs
{
    n               (__nx_ny_nz__);
}

// ************************************************************************* //
```

#### 2.2 Case Definition JSON File

The case definition JSON file must located in the templated OpenFOAM directory. This file defines a list of cases with the different parameter values for each placeholder following the format in file `cyclone-template/cyclone-cases.json`, partially pasted below:

```
{
    "cases": [
        {
            "directory": "case_1",
            "files": [
                {
                    "path": "system/decomposeParDict",
                    "parameters": [
                        {
                            "placeholder": "__numberOfSubdomains__",
                            "value": 4
                        },
                        {
                            "placeholder": "__nx_ny_nz__",
                            "value": "2 2 1"
                        }

                    ]
                },
```

Note that for every case the following keywords are defined:

1. `directory`: Name of the case directory. The templated OpenFOAM directory is copied to this directory. The path to this directory is relative to the job directory in the remote machine (see input form parameters > job directory)
2. `files`: A list of templated files with their paths and parameters specified with the `path` and `parameters` keys, respectively. The parameters are specified as a list of dictorionaries defining the parameter placeholder and its corresponding value. This tells the workflow to replace every instance of `__numberOfSubdomains__` in file `case_1/system/decomposeParDict` with the value `4`.

#### 2.3 Allrun File

A bash script named `Allrun` must be located in the templated OpenFOAM directory. The workflow calls this file from the sbatch slurm script.

### 3. Input Form Parameters

Hover over the parameters in the input form for further information.
