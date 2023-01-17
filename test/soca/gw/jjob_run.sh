#!/bin/bash
bindir=$1
srcdir=$2

# export env. var.
source "${srcdir}/test/soca/gw/runtime_vars.sh" "${bindir}" "${srcdir}"

# detemine machine from config.base
machine=$(echo `grep 'machine=' $EXPDIR/config.base | cut -d"=" -f2` | tr -d '"')

# run DA jjob
if [[ ${machine} == 'CONTAINER' ]]; then
    "${HOMEgfs}/jobs/JGDAS_GLOBAL_OCEAN_ANALYSIS_RUN"
else
    sbatch --ntasks=16 \
           --account=da-cpu \
           --qos=debug \
           --time=00:10:00 \
           --export=ALL \
           --wait "${HOMEgfs}/jobs/JGDAS_GLOBAL_OCEAN_ANALYSIS_RUN"
fi
