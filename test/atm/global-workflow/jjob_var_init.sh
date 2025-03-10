#! /usr/bin/env bash

set -x
bindir=$1
srcdir=$2

# Set g-w HOMEgfs
topdir=$(cd "$(dirname "$(readlink -f -n "${bindir}" )" )/../../.." && pwd -P)
export HOMEgfs=$topdir

# Set variables for ctest
export PSLOT=gdas_test
export EXPDIR=$bindir/test/atm/global-workflow/testrun/experiments/$PSLOT
export PDY=20210323
export cyc=18
export CDATE=${PDY}${cyc}
export ROTDIR=$bindir/test/atm/global-workflow/testrun/ROTDIRS/$PSLOT
export RUN=gdas
export CDUMP=gdas
export DATAROOT=$bindir/test/atm/global-workflow/testrun/RUNDIRS/$PSLOT
export COMIN_GES=${bindir}/test/atm/bkg
export pid=${pid:-$$}
export jobid=$pid
export COMROOT=$DATAROOT
export NMEM_ENS=3
export ACCOUNT=da-cpu
export COM_TOP=$ROTDIR

# Set GFS COM paths
source "${HOMEgfs}/ush/preamble.sh"
source "${HOMEgfs}/parm/config/gfs/config.com"

# Set python path for workflow utilities and tasks
wxflowPATH="${HOMEgfs}/ush/python"
PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}${wxflowPATH}"
export PYTHONPATH

# Detemine machine from config.base
machine=$(echo `grep 'machine=' $EXPDIR/config.base | cut -d"=" -f2` | tr -d '"')

# Set NETCDF and UTILROOT variables (used in config.base)
if [[ $machine = 'HERA' ]]; then
    NETCDF=$( which ncdump )
    export NETCDF
    export UTILROOT="/scratch2/NCEPDEV/ensemble/save/Walter.Kolczynski/hpc-stack/intel-18.0.5.274/prod_util/1.2.2"
elif [[ $machine = 'ORION' || $machine = 'HERCULES' ]]; then
    ncdump=$( which ncdump )
    NETCDF=$( echo "${ncdump}" | cut -d " " -f 3 )
    export NETCDF
    export UTILROOT=/work2/noaa/da/python/opt/intel-2022.1.2/prod_util/1.2.2
fi

# Set date variables for previous cycle
GDATE=`date +%Y%m%d%H -d "${CDATE:0:8} ${CDATE:8:2} - 6 hours"`
gPDY=$(echo $GDATE | cut -c1-8)
gcyc=$(echo $GDATE | cut -c9-10)
GDUMP="gdas"

# Set file prefixes
gprefix=$GDUMP.t${gcyc}z
oprefix=$CDUMP.t${cyc}z

# Generate COM variables from templates
YMD=${PDY} HH=${cyc} declare_from_tmpl -rx COM_OBS
RUN=${GDUMP} YMD=${gPDY} HH=${gcyc} declare_from_tmpl -rx \
    COM_ATMOS_ANALYSIS_PREV:COM_ATMOS_ANALYSIS_TMPL \
    COM_ATMOS_HISTORY_PREV:COM_ATMOS_HISTORY_TMPL \
    COM_ATMOS_RESTART_PREV:COM_ATMOS_RESTART_TMPL

# Link observations
dpath=gdas.$PDY/$cyc/obs
mkdir -p $COM_OBS
flist="amsua_n19.$CDATE sondes.$CDATE"
for file in $flist; do
   ln -fs $GDASAPP_TESTDATA/lowres/$dpath/${oprefix}.${file}.nc4 $COM_OBS/${oprefix}.${file}.nc
done

# Link radiance bias correction tarball
dpath=gdas.$gPDY/$gcyc/analysis/atmos
mkdir -p $COM_ATMOS_ANALYSIS_PREV
flist="rad_varbc_params.tar"
for file in $flist; do
   ln -fs $GDASAPP_TESTDATA/lowres/$dpath/$gprefix.${file} $COM_ATMOS_ANALYSIS_PREV/$gprefix.${file}
done


# Link atmospheric history on gaussian grid
dpath=gdas.$gPDY/$gcyc/model/atmos/history
mkdir -p $COM_ATMOS_HISTORY_PREV
flist="atmf006.nc"
for file in $flist; do
   ln -fs $GDASAPP_TESTDATA/lowres/$dpath/${gprefix}.${file} $COM_ATMOS_HISTORY_PREV/${gprefix}.${file}
done

# Link atmospheric histories on native cubed-sphere grid
flist=("cubed_sphere_grid_atmf006.nc" "cubed_sphere_grid_sfcf006.nc")
for file in "${flist[@]}"; do
   ln -fs $GDASAPP_TESTDATA/lowres/$dpath/${gprefix}.${file} $COM_ATMOS_HISTORY_PREV/${gprefix}.${file}
done

# Link member atmospheric background on tiles and atmf006
dpath=enkfgdas.$gPDY/$gcyc
for imem in $(seq 1 $NMEM_ENS); do
    memchar="mem"$(printf %03i $imem)

    MEMDIR=${memchar} RUN=enkf${RUN} YMD=${gPDY} HH=${gcyc} declare_from_tmpl -x \
	COM_ATMOS_HISTORY_PREV_ENS:COM_ATMOS_HISTORY_TMPL \
	COM_ATMOS_RESTART_PREV_ENS:COM_ATMOS_RESTART_TMPL
    COM_ATMOS_RESTART_PREV_DIRNAME_ENS=$(dirname $COM_ATMOS_RESTART_PREV_ENS)

    source=$GDASAPP_TESTDATA/lowres/$dpath/$memchar/model/atmos/history
    target=$COM_ATMOS_HISTORY_PREV_ENS
    mkdir -p $target
    rm -rf $target/enkfgdas.t${gcyc}z.atmf006.nc
    ln -fs $source/enkfgdas.t${gcyc}z.atmf006.nc $target/

    source=$GDASAPP_TESTDATA/lowres/$dpath/$memchar/model/atmos/history
    target=$COM_ATMOS_HISTORY_PREV_ENS
    flist=("cubed_sphere_grid_atmf006.nc" "cubed_sphere_grid_sfcf006.nc")
    for file in "${flist[@]}"; do
        rm -rf $target/enkf${gprefix}.${file}
        ln -fs $source/enkf${gprefix}.${file} $target/
    done
done


# Execute j-job
if [[ $machine = 'HERA' || $machine = 'ORION' || $machine = 'HERCULES' ]]; then
    sbatch --ntasks=1 --account=$ACCOUNT --qos=batch --time=00:10:00 --export=ALL --wait --output=atmanlinit-%j.out ${HOMEgfs}/jobs/JGLOBAL_ATM_ANALYSIS_INITIALIZE
else
    ${HOMEgfs}/jobs/JGLOBAL_ATM_ANALYSIS_INITIALIZE
fi
