#!/usr/bin/env bash
# ==================================================
# This is a fork of "convert_metadata.sh"
# It uses a switch case to perform
# either export or import options
# ==================================================

# Updates:
#       - Include "ARG USAGE" in CONFIG SECTION
#       - Create a "FUNCTION DEFINITIONS" SECTION
#       - Create a function for Python Module load and Usage description
#       - Create a Switch case structure based on selected operation
#       - Loop Import and certain export operations on the file_with_nsnames contents
#
# Example Usage :
# ./convert_metadata_with_switch.sh import file_with_nsnames.txt 
# ./convert_metadata_with_switch.sh export file_with_nsnames.txt
#
# ARG USAGE:
# $1 - import (or) export [This argument helps run the relevant operation]
# $2 - filename containing list of namespaces/project [file_with_nsnames.txt]
# ==================================================

########CONFIG#######################
OLD_CLUSTER_URL='https://www.example.com:8443'
NEW_CLUSTER_URL='https://www.example.com:8443'
OLD_NFS_SERVER='nfs.example.com'
OLD_NFS_PATH='/sp180001_statwb_dev/'
NEW_NFS_SERVER='nfs.example.comt'
NEW_NFS_PATH='/data/registry/'
#PRJ='jhks'
SCRIPT_TMP_DIR="${HOME}/pvmove_tmpdir"
PY3_MODULE='Python/3.7.2-GCCcore-8.2.0'
PY3_YAML_MODULE='PyYAML/5.1-GCCcore-8.2.0'


RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'
PURPLE='\033[0;35m'

########END OF CONFIG###############

# ------------------ FUNCTION DEFINITIONS ----------------

function openshift_login () {
    oc login --server=$1
    current_cluster_url=$(oc config view --minify -o jsonpath='{.clusters[*].cluster.server}')
    logged=$(oc whoami)
    if [ -z "${logged}" ] || [ "$current_cluster_url" != "$1" ]; then
        echo -e "${RED}You should be logged in in Openshift before executuig this script${NOCOLOR}"
        exit 1;
    fi
}


function openshift_logout () {
    oc logout
    logged=$(oc whoami 2>/dev/null)
    if [ -n "${logged}" ] ; then
        echo -e "${RED}I can't log out. HELP!${NOCOLOR}"
        exit 1;
    fi
}

function pymod_load () {
    echo -e "${PURPLE}Loading Python Modules...${NOCOLOR}"
    module load $PY3_MODULE $PY3_YAML_MODULE
    if [ $? -ne 0 ]; then 
        echo -e "${RED}I can't load environment Python module${NOCOLOR}"
        exit 1
    else
        echo -e "${GREEN}Python Modules Loaded successfully.${NOCOLOR}"
    fi
}

function usage_func () {
    echo  -e "${RED}\nThis script exports and imports PV and PVC.${NOCOLOR}"
    echo -e "\nImport Usage:\n\t$(realpath $0) import FILE_NAME_WITH_PROJECTS_LIST\n"
    echo -e "\nExport Usage:\n\t$(realpath $0) export FILE_NAME_WITH_PROJECTS_LIST\n"
    exit 1
}

# --------------- END OF FUNCTION DEFINITIONS ------------

##Preparations

if [ "$#" -ne 2 ]; then
    usage_func
fi

case $1 in
    ([Ee][Xx][Pp][Oo][Rr][Tt]) echo -e "${PURPLE}Preparing Export Operation...${NOCOLOR}"
                               rm -rf $SCRIPT_TMP_DIR
                               mkdir -p ${SCRIPT_TMP_DIR}/{pv_old,pv_new,pvc_old,pvc_new}

                               pymod_load

                               openshift_login ${OLD_CLUSTER_URL}

                               # Iterating on the projects specified in the file_with_nsnames

                               echo -e "${PURPLE}Verifying the project list...${NOCOLOR}"
                               for PRJ in `cat $2`
                               do
                                    if [ `oc get projects | awk '{print $1}' | grep -v NAME | grep -c ${PRJ}` -eq 0 ]; then
                                        echo -e "${RED}The project ${PRJ} does not exist in cluster ${OLD_CLUSTER_URL}.${NOCOLOR}"
                                        echo -e "${RED}Please verify the list of projects in $2.${NOCOLOR}"
                                        exit 1
                                    fi
                               done
                               echo -e "${GREEN}Project List verified.${NOCOLOR}"


                               for PRJ in `cat $2`
                               do
                                    oc project ${PRJ}
                                    
                                    ### PV ###

                                    echo -e "${PURPLE}Checking PV Information for Project - ${PRJ}...${NOCOLOR}"
                                    pvlist_raw=$(oc get pvc -n ${PRJ} | awk '{print $3}' | grep -v VOLUME)
                                    if [ -z "${pvlist_raw}" ]; then
                                        echo -e "${RED}There're no permanent volumes for this project${NOCOLOR}"
                                        exit 1;
                                    fi

                                    echo -e "${GREEN}PVs for this project are:${NOCOLOR} "$pvlist_raw

                                    PVLIST=($(echo "$pvlist_raw" | tr ',' '\n'))
                                    echo -e "${PURPLE}Exporting PV...${NOCOLOR}"
                                    for permanent_volume in "${PVLIST[@]}"; do
                                        oc export pv $permanent_volume >${SCRIPT_TMP_DIR}/pv_old/${PRJ}__${permanent_volume}.yaml
                                        if [ $? -ne 0 ]; then 
                                            echo -e "${RED}I can't export PV ${permanent_volume}${NOCOLOR}"; exit 1;  
                                        else
                                            echo -e "${GREEN}PV ${permanent_volume} exported as ${NOCOLOR} ${PRJ}__${permanent_volume}.yaml"
                                        fi
                                        
                                        echo -e "${PURPLE}Converting Metadata for ${permanent_volume} Manifest...${NOCOLOR}"

                                        ./pv_convert.py ${SCRIPT_TMP_DIR}/pv_old/${PRJ}__${permanent_volume}.yaml ${SCRIPT_TMP_DIR}/pv_new/${PRJ}__${permanent_volume}.yaml ${OLD_NFS_SERVER} ${OLD_NFS_PATH} ${NEW_NFS_SERVER} ${NEW_NFS_PATH}
                                        
                                        if [ $? -ne 0 ]; then 
                                            echo -e "${RED}I can't convert PV ${permanent_volume}${NOCOLOR}"; exit 1;
                                        else
                                            echo -e "${GREEN}Conversion Successful.${NOCOLOR}"
                                        fi
                                    done

                                    ### PVC ###
                                    
                                    echo -e "${PURPLE}Exporting PVC..${NOCOLOR}"
                                    pvclist_raw=$(oc get pvc -n ${PRJ} | awk '{print $1}' | grep -v NAME)
                                    
                                    if [ -z "${pvclist_raw}" ]; then
                                        echo -e "${RED}There're no permanent volume claims in this project${NOCOLOR}"
                                        exit 1;
                                    fi

                                    echo -e "${GREEN}PVCs for this project are: ${NOCOLOR}"$pvclist_raw #Just for our information. We don't actually need PVC list

                                    oc export pvc -n ${PRJ}  >${SCRIPT_TMP_DIR}/pvc_old/${PRJ}__pvc.yaml

                                    if [ $? -ne 0 ]; then 
                                        echo -e "${RED}I can't export PVC list${NOCOLOR}"; exit 1;
                                    else
                                        echo -e "${GREEN}PVCs exported successfully.${NOCOLOR}"
                                    fi

                                    echo -e "${PURPLE}Converting Metadata for PVC Manifests...${NOCOLOR}"

                                    ./pvc_convert.py ${SCRIPT_TMP_DIR}/pvc_old/${PRJ}__pvc.yaml ${SCRIPT_TMP_DIR}/pvc_new/${PRJ}__pvc.yaml
                                    
                                    if [ $? -ne 0 ]; then 
                                    echo -e "${RED}I can't convert PVC list${NOCOLOR}"; exit 1;
                                    else
                                    echo -e "${GREEN}Conversion Successful.${NOCOLOR}"
                                    fi

                               done
                               
                               echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
                               openshift_logout

                               #End of export and convertation

                               ;;
    ([Ii][Mm][Pp][Oo][Rr][Tt]) echo -e "${PURPLE}Preparing Import Operation...${NOCOLOR}"
                               
                               pymod_load

                               openshift_login ${NEW_CLUSTER_URL}

                               for PRJ in `cat $2`
                               do
                                    oc project ${PRJ}
                                    if [ $? -ne 0 ]; then 
                                        echo -e "${PURPLE}The project ${PRJ} does not exist. Creating project ${PRJ}...${NOCOLOR}"
                                        oc new-project ${PRJ}
                                        if [ $? -ne 0 ]; then 
                                            echo -e "${RED}I can't create project${PRJ}${NOCOLOR}"; exit 1;  
                                        else
                                            echo -e "${GREEN}Project ${PRJ} created successfully.${NOCOLOR}"
                                        fi
                                    fi
                               done
                               
                               # Excluding the following step as the YAML manifests
                               # contain the namespace field, causing the creation 
                               # of the resources in the respective namespaces 

                               #oc project ${PRJ}
                               
                               ### PV ###

                               echo -e "${PURPLE}Import PVs${NOCOLOR}"
                               for PVFILE in `ls ${SCRIPT_TMP_DIR}/pv_new/`
                               do
                                _PRJ=`echo ${PVFILE} | awk -F"__" '{print $1}'`
                                permanent_volume=`echo ${PVFILE} | awk -F"__" '{print $2}'`
                                echo -e "${PURPLE}Importing PV ${permanent_volume} for project - ${_PRJ} ....${NOCOLOR}"
                                oc create -f ${SCRIPT_TMP_DIR}/pv_new/${PVFILE}
                                if [ $? -ne 0 ]; then 
                                    echo -e "${RED}I can't import pv ${permanent_volume}  for the project ${PRJ}${NOCOLOR}"
                                else
                                    echo -e "${GREEN}Imported ${permanent_volume} for Project - ${_PRJ}, successfully.${NOCOLOR}"
                                fi  
                               done

                               ### PVC ###

                               echo -e "${PURPLE}Import PVCs${NOCOLOR}"
                               for PVCFILE in `ls ${SCRIPT_TMP_DIR}/pvc_new/`
                               do
                                    _PRJ=`echo ${PVCFILE} | awk -F"__" '{print $1}'`
                                    echo -e "${PURPLE}Importing PVCs for Project - ${_PRJ} ....${NOCOLOR}"
                                    oc create -f ${SCRIPT_TMP_DIR}/pvc_new/${PVCFILE} -n ${_PRJ}
                                    if [ $? -ne 0 ]; then 
                                        echo -e "${RED}I can't import PVCs for the project ${_PRJ}${NOCOLOR}"; exit 1;
                                    else
                                        echo -e "${GREEN}Imported PVCs for Project - ${_PRJ}, successfully.${NOCOLOR}"
                                    fi
                               done
                               
                               # oc get pvc -n ${PRJ}
                               echo -e "${PURPLE}Logging out from the new cluster${NOCOLOR}"
                               openshift_logout

                               ;;
    *) usage_func
       ;;
esac






