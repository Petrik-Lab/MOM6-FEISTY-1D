#!/bin/bash
#
# THIS SCRIPT ALLOWS TO LOOP THE 1D COLUNM RUN OF THE ONLINE/OFFLINE 
# COBALT-FEISTY FOR A GIVEN LOCATION
# 
# CONTACT: REMY DENECHERE <RDENECHERE@UCSD.EDU>
#        : JARED BRZENSKI <JABRZENSKI@UCSD.EDU>
#
# usage: ./run_multiyear_offline.sh 
#
# RUN THIS SCRIPT FROM THE CEFI/EXPS/OM4 DIRECTORY
#
# REQUIRES ENVIRONMENT VARIABLES:
#
# CEFI_DATASET_LOC     -> the location of the dataset, which link_databse needs
# CEFI_EXECUTABLE_LOC  -> the location of MOM6SIS2 you want to run
# SCRATCH_DIR          -> location you want to work from, must exist!!!
# SAVE_DIR             -> location of the final saved files. 
#
# 
# Example MPI command to run this without this script:
# MPI_COMMAND="mpiexec -np 1 ./MOM6SIS2"
#
###############################################################################
#
#FUNCTION TO KILL ALL SPAWNED PROCESSES
cleanup() {
  echo "Terminating all spawned processes..."
  echo "Check the SCRATCH directory for any stray files."
  echo "Killing processes DOES NOT clean up the file system."
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null
  done
  exit 0
}

# EMPTY ARRAY 
pids=()

# Trap Ctrl-C (SIGINT) and call cleanup function
trap cleanup SIGINT

# CHECK IF THE CORRECT NUMBER OF ARGUMENTS ARE PROVIDED
if [ "$#" -lt 3 ]; then
    echo ""
    echo "Usage: $0 <Location name> <number of year> <Unique_Name> optional:<ONLINE/OFFLINE>, default:ONLINE"
    exit 1
fi

# ASSIGN ARGUMENTS TO VARIABLES
LOC=$1
NUM_YEARS=$2
EXP=$3
if [ "$#" -eq 4 ]; then
    OFFLINE_IN=$4
else
    OFFLINE_IN="ONLINE"
fi

# Print the values of the arguments
echo "Location name: $LOC"
echo "Number of years: $NUM_YEARS"
echo "CPU core: $CPU_CORE"
echo "Experiment name: $EXP"
echo "Online/Offline mode: $OFFLINE_IN"


###############################################################################
# CHECK TO SEE IF OTHER ENVIRONMENTAL VARIABLES ARE SET
if [ -z "${CEFI_DATASET_LOC}" ]; then
    echo "CEFI_DATASET_LOC is not set, exiting"
    exit 1
elif [ -z "${CEFI_EXECUTABLE_LOC}" ]; then
    echo "CEFI_EXECUTABLE_LOC not set, exiting"
    exit 1
elif [ -z "${SCRATCH_DIR}" ]; then
    echo "SCRATCH_DIR not set, exiting."
    exit 1
elif [ -z "${SAVE_DIR}" ]; then
    echo "SAVE_DIR not set, exiting"
    exit 1
else
    echo "Found all environmental variables, continuing..."
fi

###############################################################################
# Set OFFLINE value to true/false (1,0)
if [ "$OFFLINE_IN" == "OFFLINE" ]; then
    OFFLINE=true
    echo "Setting OFFLINE to true. No FEISTY will be used."
else 
    OFFLINE=false
    echo "Setting OFFLINE to false. FEISTY submodules will be used."
fi

###############################################################################
# SET HOME DIRECTORY
HOME_DIR=$(pwd)

# This variable will be set by a overlord
UNIQUE_ID=10

# SETUP FOLDER FOR PARALLES RUNS
LONG_NAME="${OFFLINE_IN}/${LOC}"
WORK_DIR="${SCRATCH_DIR}/${LONG_NAME}"
if [ -d "$WORK_DIR" ]; then
    echo "$WORK_DIR" exists 
else 
    cd "${SCRATCH_DIR}"
    if [ -d "${OFFLINE_IN}" ]; then
        echo "${OFFLINE_IN} directory exists"
    else
        echo "${OFFLINE_IN} directory does not exist, making it..."
        mkdir "${OFFLINE_IN}"
    fi
    cd "${OFFLINE_IN}"
    mkdir "${LOC}"
    cd "${HOME_DIR}"
fi

# CHECK IF THE WORKING DIRECTORY EXISTS
if [ -d "$WORK_DIR" ]; then
	echo "${WORK_DIR} exists, continuing..."
else
	echo "${WORKDIR} does not exist, exiting..."
	exit 1
fi

###############################################################################
# COPY EVERYTHING TO THE SCRATCH DIRECTORY
# clean work dir
echo "Copying EVERYTHING! to the WORK_DIR"
rm -rf "${WORK_DIR}"/*
cp -rfL * "${WORK_DIR}"
echo "Copy complete!"
echo ""

# MOVE TO WORKING DIRECTORY
cd "${WORK_DIR}"

# MAKE THE RUNS DIRECTORY
if [ -d "${WORK_DIR}/RUNS" ]; then
    echo "RUNS Directory exists."
else
    echo "RUNS Directory does not exist, making it..."
    mkdir RUNS
fi

# NO NEED TO EDIT THE INPUT FILE
cd INPUT/
/project/rdenechere/CEFI-regional-MOM6-FEISTY/link_database.sh "${LOC}"
cd ..

#########################################################
#   SET do_FEISTY BASED ON OFFLINE/ONLINE MODE
#########################################################
# Check if do_FEISTY exists in input.nml
if grep -qi 'do_FEISTY' input.nml; then
    if [ "$OFFLINE" = true ]; then
        echo "OFFLINE mode: Setting do_FEISTY = .false. (no FEISTY)"
        sed -E -i 's/^([[:space:]]*do_FEISTY[[:space:]]*=[[:space:]]*)\.[Tt][Rr][Uu][Ee]\./\1.false./' input.nml
        sed -E -i 's/^([[:space:]]*do_FEISTY[[:space:]]*=[[:space:]]*)\.[Ff][Aa][Ll][Ss][Ee]\./\1.false./' input.nml
    else
        echo "ONLINE mode: Setting do_FEISTY = .true. (with FEISTY)"
        sed -E -i 's/^([[:space:]]*do_FEISTY[[:space:]]*=[[:space:]]*)\.[Tt][Rr][Uu][Ee]\./\1.true./' input.nml
        sed -E -i 's/^([[:space:]]*do_FEISTY[[:space:]]*=[[:space:]]*)\.[Ff][Aa][Ll][Ss][Ee]\./\1.true./' input.nml
    fi
    echo "do_FEISTY update complete."
else
    echo "WARNING: do_FEISTY not found in input.nml"
    exit 1
fi

#########################################################
#  CHECK IF MODEL IS IN RESTART OR INITIALIZATION MODE 
#  MODEL SHOULD BE IN INITIALIZATION MODE
#########################################################
# Check if the line contains input_filename = 'r' in input.nml
if grep -q "input_filename = 'r'" input.nml; then
    echo "Found 'input_filename = 'r'' in input.nml. Changing it to 'n'."
    sed -i "s/input_filename = 'r'/input_filename = 'n'/g" input.nml
    echo "Change complete."
else
    if grep -q "input_filename = 'n'" input.nml; then
         echo "'input_filename = 'n'' continuing..."
    else 
        echo "input_filename value not found or invalid."
        echo "Exiting..."
        exit 1
    fi
fi

####################################################
#  CREATE DIRECTORY FOR THE ECPERIEMENT
####################################################
FOLDER_SAVE_LOC="RUNS/${LOC}/${EXP}"
if [ -d "$FOLDER_SAVE_LOC" ]; then
    echo "$FOLDER_SAVE_LOC" exist 
    rm -rf "$FOLDER_SAVE_LOC"/*
    echo "Cleaning up $FOLDER_SAVE_LOC"
else 
    cd RUNS 
    if [ -d "${LOC}" ]; then
        echo "RUNS/${LOC} exists... making a new folder for ${EXP}"
        mkdir "${EXP}"
    else
        echo "RUNS/${LOC} does not exist, making it..."
        mkdir "${LOC}"
        cd "${LOC}"
        mkdir "${EXP}"
    fi
    cd "${WORK_DIR}"
fi

# CHECK IF THE WORKING DIRECTORY EXISTS
if [ -d "$FOLDER_SAVE_LOC" ]; then
    echo "${FOLDER_SAVE_LOC} exists, continuing..."
else
    echo "${FOLDER_SAVE_LOC} does not exist, exiting..."
    exit 1
fi

####################################################
#  RUN THE MODEL FOR YEAR 1 
####################################################
echo "Copying executable from ${CEFI_EXECUTABLE_LOC} to here"
yes | cp "${CEFI_EXECUTABLE_LOC}" . 
EXEC_NAME=$(basename "${CEFI_EXECUTABLE_LOC}")

mpiexec -np 1 ./"${EXEC_NAME}" |& tee stdout."${UNIQUE_ID}".env&
pids+=($!)
wait 

####################################################
# MOVE THE DATA TO A FOLDER IN RUN DIRECTORY: 
####################################################
YEAR_FOLDER_PATH="$FOLDER_SAVE_LOC/${LOC}_${OFFLINE_IN}_yr_1"
if [ -d "$YEAR_FOLDER_PATH" ]; then
    echo "$YEAR_FOLDER_PATH" exist 
    rm -rf "$YEAR_FOLDER_PATH"/*
else 
    mkdir "$YEAR_FOLDER_PATH"
fi

echo "Saving feisty files to specific YEAR_FOLDER_PATH: $YEAR_FOLDER_PATH"
yes | cp -i *feisty*.nc "$YEAR_FOLDER_PATH"
yes | cp -i 20040101.ocean_cobalt_restart.nc "$YEAR_FOLDER_PATH"
yes | cp -i 20040101.ocean_cobalt_btm.nc "$YEAR_FOLDER_PATH"
yes | cp -i 20040101.ocean_month_z.nc "$YEAR_FOLDER_PATH"
yes | cp -i 20040101.ocean_cobalt_tracers_month_z.nc "$YEAR_FOLDER_PATH"
yes | cp -i 20040101.ocean_cobalt_fluxes_int.nc "$YEAR_FOLDER_PATH"


####################################################
# Loop after 1st year: -----------------------------------
## Set up restart in input.nml file and get restart files: (OLD METHOD)
echo "Copying restart files to INPUT folder"
sed -i "s/input_filename = 'n'/input_filename = 'r'/g" input.nml
yes | cp -i RESTART/*.nc INPUT/


# LOOP THROUGH THE NUMBER OF YEARS
for ((i=2; i<=NUM_YEARS; i++))
do
    echo ""
    echo "--------------------------------------"
    echo "Running year ${i} of ${NUM_YEARS}..."
    
    # RUN THE MODEL
    mpiexec -np 1 ./"${EXEC_NAME}" |& tee stdout."${UNIQUE_ID}".env&
    pids+=($!)
    wait 

    # MOVE THE DATA TO A NEW FOLDER: 
    YEAR_FOLDER_PATH="$FOLDER_SAVE_LOC/${LOC}_${OFFLINE_IN}_yr_${i}"
    if [ -d "$YEAR_FOLDER_PATH" ]; then 
        rm -rf "$YEAR_FOLDER_PATH"/*
    else 
        mkdir "$YEAR_FOLDER_PATH"
    fi

    echo "Saving feisty files to specific YEAR_FOLDER_PATH"
    yes | cp -i *feisty*.nc "$YEAR_FOLDER_PATH"
    yes | cp -i 20040101.ocean_cobalt_restart.nc "$YEAR_FOLDER_PATH"
    yes | cp -i 20040101.ocean_cobalt_btm.nc "$YEAR_FOLDER_PATH"
    yes | cp -i 20040101.ocean_month_z.nc "$YEAR_FOLDER_PATH"
	yes | cp -i 20040101.ocean_cobalt_tracers_month_z.nc "$YEAR_FOLDER_PATH"
	yes | cp -i 20040101.ocean_cobalt_fluxes_int.nc "$YEAR_FOLDER_PATH"

    # get restart files: 
    sed -i "s/input_filename = 'n'/input_filename = 'r'/g" input.nml
    yes | cp -i RESTART/*.nc INPUT/

done

###############################################################################
# End the experiment: ---------------------------------------------------------
## save the restart files of last year for potential resimulation: 
FOLDER_SAVE_RESTART="${LOC}_yr_${NUM_YEARS}_OFFLINE_RESTART"
if [ -d "$FOLDER_SAVE_RESTART" ]; then
    echo $FOLDER_SAVE_RESTART" exist "
    echo "Cleaning up $FOLDER_SAVE_RESTART"
    rm -rf "$FOLDER_SAVE_RESTART"/*
else 
    echo $FOLDER_SAVE_RESTART" does not exist making it..."
    mkdir "$FOLDER_SAVE_RESTART"
fi

echo
echo "Saving RESTART files into FOLDER_SAVE_RESTART"
yes | cp -i RESTART/*.nc "$FOLDER_SAVE_RESTART"/

############################################
# SAVE EVERYTHING IN THE SAVE DIRECTORY
############################################
echo "Copying RUNS folder to SAVE_DIR"
yes | cp -r RUNS/* "$SAVE_DIR"
echo "Copying RESTART to SAVE_DIR"
yes | cp -r "$FOLDER_SAVE_RESTART" "${SAVE_DIR}/${LOC}"

cd "$HOME_DIR"
# REMOVE WORKING DIRECTORY AND FOLDERS, ETC...
rm -r "$WORK_DIR"

echo "Simulation done!"

## Set up restart in input.nml file and move restart files into the INPUT folder: 
sed -i "s/input_filename = 'r'/input_filename = 'n'/g" input.nml