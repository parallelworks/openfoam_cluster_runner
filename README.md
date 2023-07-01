# OpenFOAM Runner

The OpenFOAM-SLURM Workflow enables you to execute OpenFOAM cases on a SLURM cluster. To use this workflow effectively, please follow the instructions below:

1. Ensure that the OpenFOAM case directory is accessible within the cluster.
2. Take advantage of the workflow's flexibility by utilizing the option to template the OpenFOAM parameters in the case directory. This feature allows you to perform parameter sweeps with custom parameter values.
3. To define the various cases for the parameter sweep, create a JSON file called `cases.json` within the OpenFOAM case directory. This file will contain the necessary information to specify different cases and their corresponding parameter values.
4. If no JSON file is defined, the workflow will execute the OpenFOAM case directlys. However, if a JSON file is present, a new case directory will be generated for each defined case in the JSON file. Additionally, a separate job will be submitted for each case, allowing for parallel execution and efficient use of the cluster's resources.
5. For templated OpenFOAM cases, you have the flexibility to choose which parameters to expose as inputs in the workflow's input form. This user-friendly feature enables the creation of workflows that can be easily utilized by non-experts. By simply interacting with the input form, users can customize the simulation parameters without the need for direct modification of the JSON file or the OpenFOAM files. 

### 1. Workflow Details
The workflow encompasses the following tasks:
1. Creation of the OpenFOAM case directory within the designated job directory on the cluster. This step involves either copying the original OpenFOAM case or, if the case is templated, generating the corresponding case directories by replacing the placeholders with the actual values in the OpenFOAM files.
2. Generation of a SLURM batch script for each OpenFOAM case. These scripts are created in the `/pw/jobs/<job-number>/<case-name>/sbatch.sh` directory, utilizing the SLURM directives selected through the input form.
3. Submission of each case to the job queue and subsequent waiting for the jobs to complete execution.
4. Successful termination of the workflow if none of the jobs encounter any failures.
5. In the event of the workflow job being cancelled on the PW platform, the workflow will cancel all associated SLURM jobs, ensuring proper cleanup and termination of ongoing simulations.

By systematically carrying out these tasks, the workflow simplifies the execution of OpenFOAM cases on the cluster, making it accessible even to users without expertise in SLURM. The intuitive input form and automated generation of SLURM batch scripts alleviate the burden of manual configuration, enabling non-SLURM experts to effortlessly leverage the power of cluster computing. Additionally, the workflow's handling of job cancellations and potential failures ensures a smooth and reliable simulation process, providing a user-friendly experience for users of varying expertise levels.

### 2. Templated OpenFOAM Directory

To ensure proper execution, the templated OpenFOAM directory must be located within the Slurm cluster environment. To facilitate the preparation of the OpenFOAM case directory, we have included two sample templates in this repository: `cyclone-template` from the OpenFOAM Foundation and `cyclone-template-esi` from OpenFOAM ESI. These samples serve as illustrations of a templated version of the official cyclone OpenFOAM tutorial. They can be used as references to understand the structure and configuration required for a successful workflow setup.

#### 2.1 Templated Files

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

The `cases.json` file, which contains the case definitions, must be located within the templated OpenFOAM case directory. This file is responsible for defining a list of cases with their respective parameter values for each placeholder. To assist you in understanding the required format, we have provided an example in the cyclone-template/cases.json file, shown partially below:

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

Please take note of the following key details for each case:

1. `directory`: This specifies the name of the case directory. The templated OpenFOAM directory will be copied to this directory. The path to this directory is relative to the job directory on the remote machine (refer to the input form parameters > job directory section for more details).

2. `files`: This is a list of templated files along with their paths and parameters. Each file is defined with the path and parameters keys. The parameters are specified as a list of dictionaries, where each dictionary defines a parameter placeholder and its corresponding value. For example, using the provided configuration, the workflow will replace every occurrence of `__numberOfSubdomains__` in the file `case_1/system/decomposeParDict` with the value `4`.

#### 2.3 Allrun File
Ensure that a bash script named `Allrun` is present within the templated OpenFOAM directory. This script is executed from SLURM sbatch scripts. It is essential to load the OpenFOAM environment within the Allrun script (spack load, module load, source /path/to/bashrc , etc). Here's an example of how to accomplish this:

```
source /opt/openfoam9/etc/bashrc
```

### 3. Input Form Parameters
Hover over the parameters in the input form for additional information and guidance. The input form provides the option to expose placeholders defined in the cases.json file. These placeholders take precedence over the parameter values defined in the JSON file and are used to directly replace the placeholders within the OpenFOAM input files.

Additionally, the input form allows you to expose any SLURM directive, which will be incorporated into the generated sbatch scripts for each OpenFOAM case.

By leveraging the flexibility of the input form, you can conveniently customize the OpenFOAm and SLURM parameter values for your simulations. The workflow dynamically applies these values to the appropriate locations, ensuring accurate and tailored simulations across multiple OpenFOAM cases. This user-friendly approach simplifies the configuration process, allowing users of varying expertise levels to effortlessly harness the capabilities of the workflow.

### 4. Logs

Logs are located in the `/pw/jobs/<job-number>` directory:

1. `std.out`: Workflow standard output
2. `std.err`: Workflow standard error
3. `<case-dir>/pw-<job-number>.out`: Slurm job standard output and error for each case

And in the corresponding job directory in the cluster.
