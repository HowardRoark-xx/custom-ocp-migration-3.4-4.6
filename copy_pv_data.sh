#!/bin/bash

########################################## 
# Requires dzdo 
#     1. Create Dir
#     2. Sync file
#     3. Change ownership, if any
########################################## 
#ADD new values to config
# OCP4_ROOT
# OCP3_ROOT
# OCP3_HOST

# Source the Config file
########CONFIG#######################
source ./config
. ./ocfunction.sh --source-only
########END OF CONFIG###############

function display_usage () {
  echo "$0 Remote_server project-name [pv: optional]"
  exit 1;
}

if [[ -z $OCP4_ROOT || -z $OCP3_ROOT || -z $OCP3_HOST  ]]; then
    echo  -e "${RED} Remote path missing OCP4_ROOT: $OCP4_ROOT ,OCP3_ROOT: $OCP3_ROOT or  OCP3_HOST: $OCP3_HOST  ${NOCOLOR}"
    exit 1;
fi

if [[ "$#" -lt 2 ]] ; then
    display_usage
fi


if [[ "$#" -gt 3 ]]; then
   display_usage
fi

if [[ "$#" -eq 1 ]]; then
   REMOTE_SERVER=$1
fi

if [[ "$#" -eq 2 ]]; then
    REMOTE_SERVER=$1
    PRJ=$2
fi

if [[ "$#" -eq 3 ]]; then
  #pv is given as input
  SKIP_PV=1
  REMOTE_SERVER=$1
  PRJ=$2
  PV_PATH=$3
  echo  -e "${RED}Creating PV $PV_PATH on Remote host $REMOTE_SERVER ... ${NOCOLOR}"
  # add dzdo & remove the
  ssh -l ${USER} $REMOTE_SERVER "dzdo mkdir -m 777 -p $OCP4_ROOT/$PV_PATH"
fi
# Retrive the PV

if [[ $SKIP_PV -ne 1 ]]; then
    openshift_login ${OLD_CLUSTER_URL} ${OLD_OC}
    $OLD_OC project ${PRJ}
    if [ $? -ne 0 ]; then 
        echo "The project ${PRJ} does not exist in cluster ${OLD_CLUSTER_URL}.";
        exit 1;
    fi

    # remotely create the directory on the target machine
    
    pvs=$($OLD_OC get pvc -o go-template='{{range .items}}{{.spec.volumeName}}{{"\n"}}{{end}}')
    for pv in $pvs
    do
        PV_PATH=$(basename $($OLD_OC get pv $pv -o go-template='{{.spec.nfs.path}}'))
        echo  -e "${RED}Creating PV $pv on Remote host $REMOTE_SERVER and $PV_PATH... ${NOCOLOR}"
        # add dzdo 
        ssh -l ${USER} $REMOTE_SERVER "dzdo mkdir -m 777 -p $OCP4_ROOT/$PV_PATH" 
    done 

    echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
    #openshift_logout $OLD_OC
fi 
# rsync the data 
#rsync -vuar host1:/var/www host2:/var/www
if [[ $SKIP_PV -ne 1 ]]; then
    for pv in $pvs
    do
        PV_PATH=$(basename $($OLD_OC get pv $pv -o go-template='{{.spec.nfs.path}}'))
        if [[ -z $PV_PATH ]]; then
            echo "No Path exist ... exiting... "
        fi
        echo  -e "${RED}Copying PV $pv on Remote host $REMOTE_SERVER ... ${NOCOLOR}"
        echo " $OCP3_HOST:$OCP3_ROOT/$PV_PATH $REMOTE_SERVER:$OCP4_ROOT/$PV_PATH"
        #Change this to SSH
        #rsync -vuar $OCP3_ROOT/$PV_PATH $REMOTE_SERVER:$OCP4_ROOT/$PV_PATH
    done 
    openshift_logout $OLD_OC
else 
    if [[ -z $PV_PATH ]]; then
         echo "No Path exist ... exiting... "
    fi
    echo " $OCP3_HOST:$OCP3_ROOT/$PV_PATH $REMOTE_SERVER:$OCP4_ROOT/$PV_PATH"
    #Change this to SSH
    #rsync -vuar $OCP3_HOST:$OCP3_ROOT/$PV_PATH $REMOTE_SERVER:$OCP4_ROOT/$PV_PATH
fi
