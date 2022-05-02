#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='dcmove_tmpdir'
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
    echo  -e "${RED}This script exports and imports DC.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME [import|export]\n"
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
    mkdir -p ${SCRIPT_TMP_DIR}/${PRJ}/{dc_old,dc_new}
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


   
    echo -e "${PURPLE}Exporting DC...${NOCOLOR}"
    dclist_raw=$($OLD_OC get dc -n ${PRJ} | awk '{print $1}' | grep -v NAME)
    if [ -z "${dclist_raw}" ]; then
        echo -e "${RED}There're no deployment configs in this project${NOCOLOR}"
        exit 1;
    fi
    echo "DCs for this project are: "$dclist_raw
    

    $OLD_OC get dc -n ${PRJ} -o yaml  >${SCRIPT_TMP_DIR}/${PRJ}/dc_old/dc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't export DC list${NOCOLOR}"; exit 1;  fi

    #gitlabce-specific
    if [ "${PRJ}" == "gitlabce" ]; then
        sed -i "s/$OLD_ROUTE_BASENAME/$NEW_ROUTE_BASENAME/g" ${SCRIPT_TMP_DIR}/${PRJ}/dc_old/dc.yaml
    fi

    #changing metadata
    echo " ./dc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/dc_old/dc.yaml ${SCRIPT_TMP_DIR}/${PRJ}/dc_new/dc.yaml $OLD_REGISTRY_URL $NEW_REGISTRY_URL"
    ./dc_convert.py ${SCRIPT_TMP_DIR}/${PRJ}/dc_old/dc.yaml ${SCRIPT_TMP_DIR}/${PRJ}/dc_new/dc.yaml $OLD_REGISTRY_URL $NEW_REGISTRY_URL
    if [ $? -ne 0 ]; then echo -e "${RED}I can't convert DC list${NOCOLOR}"; exit 1;  fi


    echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
    openshift_logout $OLD_OC

    echo -e "${PURPLE}Logging into new cluster${NOCOLOR}"
    openshift_login ${NEW_CLUSTER_URL} $NEW_OC
    for img in $(oc get is -o go-template='{{range .items}}{{.status.dockerImageRepository}}{{"#"}}{{range .status.tags}}{{range .items}}{{.dockerImageReference}}{{"\n"}}{{end}}{{end}}{{end}}'); do
        echo -e "${PURPLE} Changing dc for image $img ${NOCOLOR}"
        image=$(echo $img | awk -F'#' '{print $1}')
        imageSha=$(echo $img | awk -F'#' '{print $2}')
        sed -i "s#$image.*#$imageSha#" ${SCRIPT_TMP_DIR}/${PRJ}/dc_new/dc.yaml
    done
    echo -e "${PURPLE} Logging out of new cluster $NEW_OC after image change${NOCOLOR}"
    openshift_logout $NEW_OC
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
    echo -e "${PURPLE}Import DCs${NOCOLOR}"
    $NEW_OC create -f ${SCRIPT_TMP_DIR}/${PRJ}/dc_new/dc.yaml
    if [ $? -ne 0 ]; then echo -e "${RED}I can't import DCs for the project ${PRJ}${NOCOLOR}"; exit 1;  fi


    #Debug info
    $NEW_OC get dc -n ${PRJ}
    openshift_logout $NEW_OC
fi
#---------- END OF IMPORT ----------
