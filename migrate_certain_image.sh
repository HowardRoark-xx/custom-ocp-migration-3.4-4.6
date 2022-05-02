#`!/usr/bin/env bash


########CONFIG#######################
source ./config
#NEW_WORKER='phchbs-sd220588.eu.novartis.net'
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
#if [ "$#" -lt 2 ]; then
if [ "$#" -lt 3 ]; then
    #echo  -e "${RED}This script exports and imports images.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME IMAGE_NAME\n"
    echo  -e "${RED}This script exports and imports images.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PROJECT_NAME IMAGE_NAME:IMAGE_TAG NEW_WORKER\n"
    exit 1
fi

PRJ=$1
IMAGE_NAME=$2
NEW_WORKER=$3

openshift_login ${OLD_CLUSTER_URL} ${OLD_OC}

iname=$(echo $IMAGE_NAME | cut -d ":" -f1)
itag=$(echo $IMAGE_NAME| cut -d ":" -f2)
image_exists=$(${OLD_OC} get is -n ${PRJ} | grep "${iname}" | grep "${itag}" )
if [ -z "$image_exists" ]; then echo -e "It seems, the project ${PRJ} has no images"; exit 1; fi


#Migration
echo -e "${PURPLE}Pulling and tagging image${NOCOLOR}"

OLD_TOKEN=$(${OLD_OC} whoami -t)
ssh -o SendEnv=$OLD_TOKEN -o SendEnv=$OLD_REGISTRY_FQDN -o SendEnv=$NEW_REGISTRY_URL -o SendEnv=$PRJ -o SendEnv=$IMAGE_NAME $(whoami)@$NEW_WORKER \
    "dzdo podman login -u $(whoami) -p ${OLD_TOKEN} ${OLD_REGISTRY_FQDN} && \
    echo \"podman pull ${OLD_REGISTRY_FQDN}/${PRJ}/${IMAGE_NAME}\" && \
    dzdo podman pull ${OLD_REGISTRY_FQDN}/${PRJ}/${IMAGE_NAME} && \
    dzdo podman tag ${OLD_REGISTRY_FQDN}/${PRJ}/${IMAGE_NAME} ${NEW_REGISTRY_URL}/${PRJ}/${IMAGE_NAME}"



echo -e "${PURPLE}Pulling images...${NOCOLOR}"
openshift_login ${NEW_CLUSTER_URL} $NEW_OC


$NEW_OC project ${PRJ}
if [ $? -ne 0 ]; then
    echo -e "${PURPLE}The project ${PRJ} does not exist. Creating project ${PRJ}...${NOCOLOR}"
    $NEW_OC new-project ${PRJ}
    if [ $? -ne 0 ]; then echo -e "${RED}I can't create project${PRJ}${NOCOLOR}"; exit 1;  fi
fi


NEW_TOKEN=$(${NEW_OC} whoami -t)
ssh -o SendEnv=$NEW_TOKEN -o SendEnv=$NEW_REGISTRY_URL -o SendEnv=$PRJ -o SendEnv=$IMAGE_NAME $(whoami)@$NEW_WORKER \
    "dzdo podman login -u $(whoami) -p ${NEW_TOKEN} ${NEW_REGISTRY_URL} && \
    dzdo podman push ${NEW_REGISTRY_URL}/${PRJ}/${IMAGE_NAME}"

echo "Let's check"
${NEW_OC} get is -n ${PRJ} | grep "${iname}" | grep "${itag}" 

openshift_logout ${NEW_OC}




