#!/usr/bin/env bash


########CONFIG#######################
source ./config
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


function get_imagelist () {

    OIFS=$IFS;
    IFS=$'\n'

    oc_cmd=$1
    project=$2

    mapfile -t imagelist_raw < <( ${oc_cmd} get is -n ${project} | grep -v "NAME" | awk '{print $1,$3}' )
    for line in ${imagelist_raw[*]}; do
        imagename=$(echo $line | awk '{print $1}')
        imagetag=$(echo $line | awk '{print $2}')
        if [ -n "$imagetag" ]; then
            imagetag=$(echo $imagetag | cut -d "," -f1) #use only first tag
            imagelist+=("$imagename:$imagetag")
        else
            imagelist+=("$imagename")
        fi
    done

}

#stolen from Fabian Lee (https://fabianlee.org/2020/09/06/bash-difference-between-two-arrays/)
function arraydiff() {
  awk 'BEGIN{RS=ORS=" "}
       {NR==FNR?a[$0]++:a[$0]--}
       END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}

# --------------- END OF FUNCTION DEFINITIONS ------------

##Preparations
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo  -e "${RED}This script exports and imports images.${NOCOLOR}\n\nUsage:\n\t$(realpath $0) PJOJECT_NAME NEW_WORKER_NODE\n"
    exit 1
fi

PRJ=$1
NEW_WORKER=$2

openshift_login ${OLD_CLUSTER_URL} ${OLD_OC}
$OLD_OC project ${PRJ}
if [ $? -ne 0 ]; then echo "The project ${PRJ} does not exist in cluster ${OLD_CLUSTER_URL}."; exit 1;  fi

declare -a imagelist=()
get_imagelist ${OLD_OC} ${PRJ}
old_imagelist=("${imagelist[@]}")

if [ -z "$old_imagelist" ]; then echo -e "It seems, the project ${PRJ} has no images"; exit 1; fi

echo -e "${PURPLE} The project ${PRJ} has the following images:${NOCOLOR}"
printf '%s\n' "${old_imagelist[@]}"


#Let's do something with the images
OLD_TOKEN=$(${OLD_OC} whoami -t)

echo -e "${PURPLE}Pulling and tagging images${NOCOLOR}"
for imagename in ${old_imagelist[*]}; do
    ssh -o SendEnv=$OLD_TOKEN -o SendEnv=$OLD_REGISTRY_FQDN -o SendEnv=$NEW_REGISTRY_URL -o SendEnv=$PRJ -o SendEnv=$imagename $(whoami)@$NEW_WORKER \
    "dzdo podman login -u $(whoami) -p ${OLD_TOKEN} ${OLD_REGISTRY_FQDN} && \
    dzdo podman pull ${OLD_REGISTRY_FQDN}/${PRJ}/${imagename} && \
    dzdo podman tag ${OLD_REGISTRY_FQDN}/${PRJ}/${imagename} ${NEW_REGISTRY_URL}/${PRJ}/${imagename}"
done


echo -e "${PURPLE}Pulling images...${NOCOLOR}"
openshift_login ${NEW_CLUSTER_URL} $NEW_OC


$NEW_OC project ${PRJ}
if [ $? -ne 0 ]; then
    echo -e "${PURPLE}The project ${PRJ} does not exist. Creating project ${PRJ}...${NOCOLOR}"
    $NEW_OC new-project ${PRJ}
    if [ $? -ne 0 ]; then echo -e "${RED}I can't create project${PRJ}${NOCOLOR}"; exit 1;  fi
fi

NEW_TOKEN=$(${NEW_OC} whoami -t)
for imagename in ${old_imagelist[*]}; do
    ssh -o SendEnv=$NEW_TOKEN -o SendEnv=$NEW_REGISTRY_URL -o SendEnv=$PRJ -o SendEnv=$imagename $(whoami)@$NEW_WORKER \
    "dzdo podman login -u $(whoami) -p ${NEW_TOKEN} ${NEW_REGISTRY_URL} && \
    dzdo podman push ${NEW_REGISTRY_URL}/${PRJ}/${imagename}"
done


#OK. Pushed. Let's get the list of the images in the new project
declare -a imagelist=()
get_imagelist ${NEW_OC} ${PRJ}
new_imagelist=("${imagelist[@]}")

echo -e "${PURPLE}Images, pushed${NOCOLOR}"
printf '%s\n' "${new_imagelist[@]}"

manual_transfer=($(arraydiff old_imagelist[@] new_imagelist[@]))

echo -e "${PURPLE}Images, pulled${NOCOLOR}"
printf '%s\n' "${old_imagelist[@]}"

if (( ${#manual_transfer[@]} != 0 )); then
  echo -e "${RED}You should fix manually the problem with the images${NOCOLOR}"
  printf '%s\n' "${manual_transfer[@]}"
fi







