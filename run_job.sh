#!/bin/bash
rm -rf /pw/jobs/00000
cp -r /pw/openfoam_runner /pw/jobs/00000
cd /pw/jobs/00000

bash main.sh \
    --controller pw.conf \
    --def_file openfoam9-paraview56.def \
    --sif_file /home/__USER__/pworks/openfoam/openfoam9-paraview56.sif \
    --chdir /home/__USER__/pworks/__job_number__ \
    --cases_json_file /home/__USER__/pworks/openfoam/cyclone-template/cyclone-cases.json \
    --partition compute \
    --time 06:00:00 \
    --numnodes 1 \
    --exclusive True 1>std.out 2>std.err