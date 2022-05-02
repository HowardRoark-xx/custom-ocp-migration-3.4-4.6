#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='sccmove_tmpdir'
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
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo  -e "${RED}This script exports and imports SCC.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) SCCNAME [import|export]\n"
    exit 1
fi

SCCNAME=$1

if [ "$(echo ${2,,})" == "import" ]; then
    action="import"
elif [ "$(echo ${2,,})" == "export" ]; then 
    action="export"
else
    action=""
fi

if [ "${action}" != "import" ]; then
    echo -e "${PURPLE}Preparing Export Operation...${NOCOLOR}"
    rm -rf $SCRIPT_TMP_DIR/${SCCNAME}
    mkdir -p ${SCRIPT_TMP_DIR}/${SCCNAME}/{scc_old,scc_new}
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

   
    echo -e "${PURPLE}Exporting SCC ${SCCNAME}...${NOCOLOR}"

    $OLD_OC get scc ${SCCNAME} -o yaml  >${SCRIPT_TMP_DIR}/${SCCNAME}/scc_old/scc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export SCC${NOCOLOR}"; exit 1;  fi



    echo " ./scc_convert.py ${SCRIPT_TMP_DIR}/${SCCNAME}/scc_old/scc.yaml ${SCRIPT_TMP_DIR}/${SCCNAME}/scc_new/scc.yaml"
    ./scc_convert.py ${SCRIPT_TMP_DIR}/${SCCNAME}/scc_old/scc.yaml ${SCRIPT_TMP_DIR}/${SCCNAME}/scc_new/scc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert SCC ${SCCNAME}${NOCOLOR}"; exit 1;  fi

    echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
    openshift_logout $OLD_OC
fi







#---------- END OF EXPORT ----------


#---------- IMPORT ----------

if [ "${action}" != "export" ]; then 
    echo -e "${PURPLE}Import...${NOCOLOR}"
    openshift_login ${NEW_CLUSTER_URL} $NEW_OC


    #SCC import
    echo -e "${PURPLE}Import SCCs${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${SCCNAME}/scc_new/scc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import SCCs ${SCCNAME}${NOCOLOR}"; exit 1;  fi


    #Debug info
    $NEW_OC get scc | grep  ${SCCNAME}
    openshift_logout $NEW_OC
fi
#---------- END OF IMPORT ----------
