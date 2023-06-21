#!/bin/bash

parseArgs() {
    rm -rf inputs.sh
    index=1
    local args=""
    for arg in $@; do
	    prefix=$(echo "${arg}" | cut -c1-6)
	    if [[ ${prefix} == '--_pw_' ]]; then
	        pname=$(echo $@ | cut -d ' ' -f${index} | sed 's/--_pw_//g')
	        pval=$(echo $@ | cut -d ' ' -f$((index + 1)))
		    # To support empty inputs (--a 1 --b --c 3)
		    if [ ${pval:0:6} != "--_pw_" ]; then
	            echo "export ${pname}=${pval}" >> $(dirname $0)/inputs.sh
	            export "${pname}=${pval}"
            fi
	    fi
        index=$((index+1))
    done
}

replace_templated_inputs() {
    echo Replacing templated inputs
    script=$1
    index=1
    for arg in $@; do
        prefix=$(echo "${arg}" | cut -c1-2)
	    if [[ ${prefix} == '--' ]]; then
	        pname=$(echo $@ | cut -d ' ' -f${index} | sed 's/--//g')
	        pval=$(echo $@ | cut -d ' ' -f$((index + 1)))
	        # To support empty inputs (--a 1 --b --c 3)
	        if [ ${pval:0:2} != "--" ]; then
                echo "    sed -i \"s|__${pname}__|${pval}|g\" ${script}"
		        sed -i "s|__${pname}__|${pval}|g" ${script}
	        fi
	    fi
        index=$((index+1))
    done
}


exportResourceInfo() {
    # Get poolname from pw.conf
    if [ -z "${poolname}" ] || [[ "${poolname}" == "pw.conf" ]]; then
        poolname=$(cat /pw/jobs/${job_number}/pw.conf | grep sites | grep -o -P '(?<=\[).*?(?=\])')
        if [ -z "${poolname}" ]; then
            echo "ERROR: Pool name not found in /pw/jobs/${job_number}/pw.conf - exiting the workflow"
            exit 1
        fi
    fi

    # No underscores and only lowercase
    poolname=$(echo ${poolname} | sed "s/_//g" |  tr '[:upper:]' '[:lower:]')
    export poolname=${poolname}

    if [[ ${controller} == "pw.conf" ]]; then
        if [ -z "${poolname}" ]; then
            echo "ERROR: Pool name not found in /pw/jobs/${job_number}/pw.conf - exiting the workflow"
            exit 1
        fi
        controller=${poolname}.clusters.pw
        controller=$(${CONDA_PYTHON_EXE} /swift-pw-bin/utils/cluster-ip-api-wrapper.py $controller)
    fi

    if [ -z "${controller}" ]; then
        echo "ERROR: No controller was specified - exiting the workflow"
        exit 1
    fi
    export controller=${controller}

    pooltype=$(${CONDA_PYTHON_EXE} utils/pool_api.py ${poolname} type)
    if [ -z "${pooltype}" ]; then
        echo "ERROR: Pool type not found - exiting the workflow"
        echo "${CONDA_PYTHON_EXE} utils/pool_api.py ${poolname} type"
        exit 1
    fi
    export pooltype=${pooltype}

    if [[ ${pooltype} == "slurmshv2" ]]; then
        poolworkdir=$(${CONDA_PYTHON_EXE} utils/pool_api.py ${poolname} workdir)
        if [ -z "${poolworkdir}" ]; then
            echo "ERROR: Pool workdir not found - exiting the workflow"
            echo "${CONDA_PYTHON_EXE} utils/pool_api.py ${poolname} workdir"
            exit 1
        fi
    else
        poolworkdir=${HOME}
    fi
    export poolworkdir=${poolworkdir}
}


getSchedulerDirectivesFromInputForm() {
    # WARNING: Only works after sourcing inputs.sh
    # Scheduler parameters in the input form are intercepted and formatted here.
    #
    # For example, it transforms arguments:
    # export host_jobschedulertype=slurm
    # export host__sch__d_N___=1
    # export service=jupyter-host
    # export host__sch__dd_cpus_d_per_d_task_e_=1
    # into:
    # ;-N___1;--cpus-per-task=1
    # Which is then processed out of this function to:
    # # SBATCH -N 1
    # # SBATCH --cpus-per-task=1
    #
    # Character mapping for special scheduler parameters:
    # 1. _sch_ --> ''
    # 1. _d_ --> '-'
    # 2. _dd_ --> '--'
    # 2. _e_ --> '='
    # 3. ___ --> ' ' (Not in this function)
    # Get special scheduler parameters
    host=$1
    sch_inputs=$(env | grep ${host}__sch_ | sed 's/.*__sch_//')
    for sch_inp in ${sch_inputs}; do
        sch_dname=$(echo ${sch_inp} | cut -d'=' -f1)
	    sch_dval=$(echo ${sch_inp} | cut -d'=' -f2)
	    sch_dname=$(echo ${sch_dname} | sed "s|_d_|-|g" | sed "s|_dd_|--|g" | sed "s|_e_|=|g")
        if ! [ -z "${sch_dval}" ] && ! [[ "${sch_dval}" == "default" ]]; then
            form_sched_directives="${form_sched_directives};${sch_dname}${sch_dval}"
        fi
    done
    echo ${form_sched_directives}
}

getBatchScriptHeader() {
    # Executor label
    elabel=$1
    scheduler_directives=$(env | grep ${elabel}_scheduler_directives | sed "s/${elabel}_scheduler_directives=//g" )
    scheduler_directives="${scheduler_directives}$(getSchedulerDirectivesFromInputForm ${elabel})"
    echo "#!/bin/bash"
    workdir=$(env | grep ${elabel}_workdir | sed "s/${elabel}_workdir=//g" )
    jobdir=${workdir}/pw/jobs/${job_number}
    jobschedulertype=$(env | grep ${elabel}_jobschedulertype | sed "s/${elabel}_jobschedulertype=//g" )
    scheduler_directives=";-o ${jobdir}/${elabel}_script.out;-e ${jobdir}/${elabel}_script.out;${scheduler_directives}"
    if [[ ${jobschedulertype} == "SLURM" ]]; then
        directive_prefix="#SBATCH"
        scheduler_directives="${scheduler_directives};--job-name=${elabel}_${job_number}"
    elif [[ ${jobschedulertype} == "PBS" ]]; then
        directive_prefix="#PBS"
        scheduler_directives="${scheduler_directives};-N___${elabel}_${job_number}"
    elif [[ ${jobschedulertype} == "CONTROLLER" ]]; then
        return
    else
        echo "ERROR: jobschedulertype <${jobschedulertype}> must be SLURM, PBS or LOCAL" >&2
        exit 1
    fi
    echo ${scheduler_directives} | sed "s|;;|;|g" | sed "s|;|;${directive_prefix} |g" | sed "s|___| |g" | tr ';' '\n'
}
