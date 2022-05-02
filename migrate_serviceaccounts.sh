#!/usr/bin/env bash


########CONFIG#######################
source ./config
SCRIPT_WORKDIR='sa_migration'
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

# --------------- PREPARRATIONS ------------
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo  -e "${RED}This script adds serviceaccounts into appropriate groups.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PROJECTNAME [import|export]\n"
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
    mkdir -p ${SCRIPT_TMP_DIR}/${PRJ}/sa
    if [ $? -ne 0 ]; then
        echo -e "${RED}I can't create work directory. Check the permissions.${NOCOLOR}"
        exit 1
    fi
fi

# --------------- END OF PREPARATIONS ------------

#---------- EXPORT ----------
if [ "${action}" != "import" ]; then

    openshift_login ${OLD_CLUSTER_URL} ${OLD_OC}
    $OLD_OC project ${PRJ}
    if [ $? -ne 0 ]; then echo -e "${RED}The project ${PRJ} does not exist in cluster ${OLD_CLUSTER_URL}.${NOCOLOR}"; exit 1;  fi
    serviceaccountlist_raw=$(${OLD_OC} get serviceaccount | awk '{print $1}' | grep -v NAME )
    SERVICEACCOUNT_LIST=($(echo "$serviceaccountlist_raw" | tr ',' '\n'))
    unset serviceaccountlist_raw

    scclist_raw=$(${OLD_OC} get scc | awk '{print $1}' | grep -v NAME)
    SCCLIST=($(echo "$scclist_raw" | tr ',' '\n'))
    unset scclist_raw

    for i in "${SCCLIST[@]}"; do
        for k in "${SERVICEACCOUNT_LIST[@]}"; do
            sa_in_scc=$(${OLD_OC} get scc $i -o yaml | grep "${PRJ}:$k")
            if [ -n "$sa_in_scc" ]; then
                echo $i >> ${SCRIPT_TMP_DIR}/${PRJ}/sa/${k}
                unset sa_in_scc
            fi
        done
    done

    echo -e "${PURPLE}Logging out from the old cluster${NOCOLOR}"
    openshift_logout $OLD_OC
    unset SCCLIST
    unset SERVICEACCOUNT_LIST

fi


#---------- END OF EXPORT ----------

#---------- IMPORT ----------
if [ "${action}" != "export" ]; then
    echo -e "${PURPLE}Import...${NOCOLOR}"
    openshift_login ${NEW_CLUSTER_URL} $NEW_OC
    unset scclist_raw
    unset serviceaccountlist_raw
    unset SCCLIST
    unset SERVICEACCOUNT_LIST

    
    filelist=$(ls ${SCRIPT_TMP_DIR}/${PRJ}/sa)
    filearray=($filelist)
 

    for i in "${filearray[@]}"; do
        mapfile -t SCCLIST < ${SCRIPT_TMP_DIR}/${PRJ}/sa/$i
        echo -e "${PURPLE}SCC for $i is ${NOCOLOR}"
        printf '%s ' "${SCCLIST[@]}" ; printf '\n'
        for k in "${SCCLIST[@]}"; do
            echo "The command will be:"
            echo "${NEW_OC}  adm policy add-scc-to-user $k system:serviceaccount:${PRJ}:$i"
            ${NEW_OC} adm policy add-scc-to-user $k system:serviceaccount:${PRJ}:$i
        done
    done
    openshift_logout $NEW_OC
fi

#---------- END OF IMPORT ----------

