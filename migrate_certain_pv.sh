#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='pvmove_tmpdir'
SCRIPT_TMP_DIR="${SCRIPT_TMP_BASEDIR}/${SCRIPT_WORKDIR}"

########END OF CONFIG###############


# ------------------ FUNCTION DEFINITIONS ----------------
function openshift_login () {
    oc_cmd=$2
    $oc_cmd login  --insecure-skip-tls-verify=true --server=$1
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
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo  -e "${RED}This script exports and imports one PV and PVC.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME VOLUMENAME [import|export]\n"
    exit 1
fi

PRJ=$1
VOLUMENAME=$2

if [ "$(echo ${3,,})" == "import" ]; then
    action="import"
elif [ "$(echo ${3,,})" == "export" ]; then 
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
    pv_exists=$($OLD_OC get pvc -n ${PRJ} | grep ${VOLUMENAME} | awk '{print $3}')

    if [ -z "${pv_exists}" ]; then
        echo -e "${RED}There're no permanent volumes in this project${NOCOLOR}"
        exit 1;
    fi
    pvclaim=$($OLD_OC get pvc -n ${PRJ} | grep ${VOLUMENAME} | awk '{print $1}')
    echo -e "${PURPLE}Pvclaim for this volume is ${pvclaim}${NOCOLOR}"    


    $OLD_OC export pv $VOLUMENAME >${SCRIPT_TMP_DIR}/${PRJ}/pv_old/${VOLUMENAME}.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export PV ${VOLUMENAME}${NOCOLOR}"; exit 1;  fi
    ./pv_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/pv_old/${VOLUMENAME}.yaml ${SCRIPT_TMP_DIR}/${PRJ}/pv_new/${VOLUMENAME}.yaml ${OLD_NFS_SERVER} ${OLD_NFS_PATH} ${NEW_NFS_SERVER} ${NEW_NFS_PATH}
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert PV ${VOLUMENAME}${NOCOLOR}"; exit 1;  fi    


    ###PVC export
    echo -e "${PURPLE}Exporting PVC..${NOCOLOR}"
    $OLD_OC export pvc ${pvclaim} -n ${PRJ} >${SCRIPT_TMP_DIR}/${PRJ}/pvc_old/${pvclaim}.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export PVC ${pvclaim}${NOCOLOR}"; exit 1;  fi
    ./single_pvc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/pvc_old/${pvclaim}.yaml ${SCRIPT_TMP_DIR}/${PRJ}/pvc_new/${pvclaim}.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert PVC ${pvclaim}${NOCOLOR}"; exit 1;  fi


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
    echo -e "${PURPLE}Import PV${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/pv_new/${VOLUMENAME}.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import pv ${VOLUMENAME}  for the project ${PRJ}${NOCOLOR}";  fi


    #PVC import
    echo -e "${PURPLE}Import PVCs${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/pvc_new/${pvclaim}.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import PVC ${pvclaim} for the project ${PRJ}${NOCOLOR}"; exit 1;  fi


    #Debug info
    $NEW_OC get pvc -n ${PRJ} | grep ${VOLUMENAME}
    openshift_logout $NEW_OC
fi
#---------- END OF IMPORT ----------
