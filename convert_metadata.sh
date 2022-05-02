#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='pvmove_tmpdir'
SCRIPT_TMP_DIR="${SCRIPT_TMP_BASEDIR}/${SCRIPT_WORKDIR}"

########END OF CONFIG###############


# ------------------ FUNCTION DEFINITIONS ----------------
function openshift_login () {
    oc_cmd=$2
    $oc_cmd login -u ${USER} --insecure-skip-tls-verify=true --server=$1
    current_cluster_url=$($oc_cmd config view --minify -o jsonpath='{.clusters[*].cluster.server}')
    logged=$($oc_cmd whoami)
    if [ -z "${logged}" ] || [ "$current_cluster_url" != "$1" ]; then
        echo -e "${RED}You should be logged in in Openshift before executuig this script${NOCOLOR}"
        exit 1;
    fi
}


function openshift_logout () {
    oc_cmd=$1
    oc logout
    logged=$($oc_cmd whoami 2>/dev/null)
    if [ -n "${logged}" ] ; then
        echo -e "${RED}I can't log out. HELP!${NOCOLOR}"
        exit 1;
    fi
}

# --------------- END OF FUNCTION DEFINITIONS ------------




##Preparations
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo  -e "${RED}This script exports and imports PV and PVC.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME [import|export]\n"
    exit 1
fi

PRJ=$1

if [ "$(echo ${2,,})" == "import" ]; then
    action="import"
elif [ "$(echo ${2,,})" == "export" ]; then 
    action="export"
else
    action=""
fi

if [ "${action}" != "import" ]; then
    echo -e "${PURPLE}Preparing Export Operation...${NOCOLOR}"
    rm -rf $SCRIPT_TMP_DIR/${PRJ}
    mkdir -p ${SCRIPT_TMP_DIR}/${PRJ}/{pv_old,pv_new,pvc_old,pvc_new}
    if [ $? -ne 0 ]; then
        echo -e "${RED}I can't create work directory. Check the permissions.${NOCOLOR}"
        exit 1
    fi
fi

module load $PY3_MODULE
if [ $? -ne 0 ]; then echo -e "${RED}I can't load environment Python module${NOCOLOR}"; exit 1;  fi
##End of preparations



#---------- EXPORT ----------

if [ "${action}" != "import" ]; then
    openshift_login ${OLD_CLUSTER_URL} ${OLD_OC}
    $OLD_OC project ${PRJ}
    if [ $? -ne 0 ]; then echo "The project ${PRJ} does not exist in cluster ${OLD_CLUSTER_URL}."; exit 1;  fi


    ###PV export
    echo -e "${PURPLE}Exporting PV...${NOCOLOR}"
    pvlist_raw=$($OLD_OC get pvc -n ${PRJ} | awk '{print $3}' | grep -v VOLUME)
    if [ -z "${pvlist_raw}" ]; then
        echo -e "${RED}There're no permanent volumes in this project${NOCOLOR}"
        exit 1;
    fi
    echo "PVs for this project are: "$pvlist_raw
    PVLIST=($(echo "$pvlist_raw" | tr ',' '\n'))


    for permanent_volume in "${PVLIST[@]}"; do
        $OLD_OC export pv $permanent_volume >${SCRIPT_TMP_DIR}/${PRJ}/pv_old/${permanent_volume}.yaml
        if [ $? -ne 0 ]; then echo -e "${RED}I can't export PV ${permanent_volume}${NOCOLOR}"; exit 1;  fi
        ./pv_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/pv_old/${permanent_volume}.yaml ${SCRIPT_TMP_DIR}/${PRJ}/pv_new/${permanent_volume}.yaml ${OLD_NFS_SERVER} ${OLD_NFS_PATH} ${NEW_NFS_SERVER} ${NEW_NFS_PATH}
        if [ $? -ne 0 ]; then echo -e "${RED}I can't convert PV ${permanent_volume}${NOCOLOR}"; exit 1;  fi    
    done


    ###PVC export
    echo -e "${PURPLE}Exporting PVC..${NOCOLOR}"
    pvclist_raw=$($OLD_OC get pvc -n ${PRJ} | awk '{print $1}' | grep -v NAME)
    if [ -z "${pvclist_raw}" ]; then
        echo -e "${RED}There're no permanent volume claims in this project${NOCOLOR}"
        exit 1;
    fi
    echo "PVCs for this project are: "$pvclist_raw #Just for our information. We don't actually need PVC list


    $OLD_OC export pvc -n ${PRJ}  >${SCRIPT_TMP_DIR}/${PRJ}/pvc_old/pvc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export PVC list${NOCOLOR}"; exit 1;  fi
    ./pvc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/pvc_old/pvc.yaml ${SCRIPT_TMP_DIR}/${PRJ}/pvc_new/pvc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert PVC list${NOCOLOR}"; exit 1;  fi


    echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
    openshift_logout $OLD_OC
fi

#---------- END OF EXPORT ----------


#---------- IMPORT ----------

if [ "${action}" != "export" ]; then 
    echo -e "${PURPLE}Import...${NOCOLOR}"
    openshift_login ${NEW_CLUSTER_URL} $NEW_OC


    $NEW_OC project ${PRJ}
    if [ $? -ne 0 ]; then 
        echo -e "${PURPLE}The project ${PRJ} does not exist. Creating project ${PRJ}...${NOCOLOR}"
        $NEW_OC new-project ${PRJ}
        if [ $? -ne 0 ]; then echo -e "${RED}I can't create project${PRJ}${NOCOLOR}"; exit 1;  fi
    fi
    $NEW_OC project ${PRJ}


    #PV import
    echo -e "${PURPLE}Import PVs${NOCOLOR}"
    if [ "${action}" == "import" ]; then #to make the import independent
        filelist=$(ls ${SCRIPT_TMP_DIR}/${PRJ}/pv_new/ | grep yaml)
        filearray=($filelist)
        PVLIST=()

        for i in "${filearray[@]}"; do
            tempvar=$(echo $i | cut -d "." -f1)
            echo $tempvar
            PVLIST+=($tempvar)
        done
    fi



    for permanent_volume in "${PVLIST[@]}"; do
      $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/pv_new/${permanent_volume}.yaml
      if [ $? -ne 0 ]; then echo -e "${RED}I can't import pv ${permanent_volume}  for the project ${PRJ}${NOCOLOR}";  fi  
    done


    #PVC import
    echo -e "${PURPLE}Import PVCs${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/pvc_new/pvc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import PVCs for the project ${PRJ}${NOCOLOR}"; exit 1;  fi


    #Debug info
    $NEW_OC get pvc -n ${PRJ}
    openshift_logout $NEW_OC
fi
#---------- END OF IMPORT ----------
