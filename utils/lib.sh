#!/bin/bash

# Exports inputs in the formart
# --a 1 --b 2 --c --d 4
# to:
# export a=1 b=2 d=4
parseArgs() {
    index=1
    args=""
    for arg in $@; do
	    prefix=$(echo "${arg}" | cut -c1-2)
	    if [[ ${prefix} == '--' ]]; then
	        pname=$(echo $@ | cut -d ' ' -f${index} | sed 's/--//g')
	        pval=$(echo $@ | cut -d ' ' -f$((index + 1)))
		    # To support empty inputs (--a 1 --b --c 3)
		    if [ ${pval:0:2} != "--" ]; then
	            echo "export ${pname}=${pval}" >> $(dirname $0)/env.sh
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
        exit 
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
