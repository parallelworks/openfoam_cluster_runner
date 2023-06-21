#!/bin/bash

#SBATCH -o /scratch/atnorth/pw/jobs//ofhost_script.out
#SBATCH -e /scratch/atnorth/pw/jobs//ofhost_script.out
#SBATCH --cpus-per-task=60
#SBATCH --partition=normal
#SBATCH --job-name=ofhost_
cd /scratch/atnorth/pw/jobs/
