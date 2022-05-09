#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='bcmove_tmpdir'
SCRIPT_TMP_DIR="${SCRIPT_TMP_BASEDIR}/${SCRIPT_WORKDIR}"
########END OF CONFIG###############


# ------------------ FUNCTION DEFINITIONS ----------------
function openshift_login () {
    oc_cmd=$2
    $oc_cmd login -u ${USER}  --insecure-skip-tls-verify=true --server=$1
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
    echo  -e "${RED}This script exports and imports BC.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME [import|export]\n"
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
    mkdir -p ${SCRIPT_TMP_DIR}/${PRJ}/{bc_old,bc_new}
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


   
    echo -e "${PURPLE}Exporting BC...${NOCOLOR}"
    bclist_raw=$($OLD_OC get bc -n ${PRJ} | awk '{print $1}' | grep -v NAME)
    if [ -z "${bclist_raw}" ]; then
        echo -e "${RED}There're no buildconfigs in this project${NOCOLOR}"
        exit 1;
    fi
    echo "BCs for this project are: "$bclist_raw
    

    $OLD_OC get bc -n ${PRJ} -o yaml  >${SCRIPT_TMP_DIR}/${PRJ}/bc_old/bc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export BC list${NOCOLOR}"; exit 1;  fi
    echo " ./bc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/bc_old/bc.yaml ${SCRIPT_TMP_DIR}/${PRJ}/bc_new/bc.yaml $OLD_REGISTRY_URL $NEW_REGISTRY_URL"
    ./bc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/bc_old/bc.yaml ${SCRIPT_TMP_DIR}/${PRJ}/bc_new/bc.yaml $OLD_REGISTRY_URL $NEW_REGISTRY_URL
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert BC list${NOCOLOR}"; exit 1;  fi


    echo -e "${PURPLE} Converting the git repo link ${NOCOLOR}"
    sed -i "s#gitlabce.example.com#gitlabce.apps.ocp4.example.com#" ${SCRIPT_TMP_DIR}/${PRJ}/bc_new/bc.yaml

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


    #DC import
    echo -e "${PURPLE}Import BCs${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/bc_new/bc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import BCs for the project ${PRJ}${NOCOLOR}"; exit 1;  fi


    #Debug info
    $NEW_OC get bc -n ${PRJ}
    openshift_logout $NEW_OC
fi
#---------- END OF IMPORT ----------
