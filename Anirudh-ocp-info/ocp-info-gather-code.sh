#!/usr/bin/bash

echo "NAME|DISPLAY_NAME|CREATION_TIMESTAMP|CREATOR|MEMBERS" >> tmp_prj_info.txt && \
for PRJ in `oc get projects | awk '{print $1}' | egrep -v "NAME|management-infra|default|openshift|nvs-oam|nvs-rstudio-ide|logging|kube-system|cicd|nvs-shinys2i|solace|redmine|ocp-ops-view|nerecr" | sort`;
do
PRJ_DISPL_NAME=`oc get project ${PRJ} -o yaml | grep display-name | awk -F":" '{print $2}' | tr -d " "`
PRJ_REQ=`oc get project ${PRJ} -o yaml | grep requester | awk -F":" '{print $2}' | tr -d " "`
PRJ_MEM=`oc get rolebindings -n ${PRJ} -o jsonpath='{range .items[*]}{.userNames}{"\n"}{end}' | egrep -v "nil|serviceaccount" | tr -d "\n" | cut -c 2- | sed 's/.$//' | sed 's/\]\[/\ /' | tr " " ";"`
CRT_TS=`oc get project ${PRJ} -o jsonpath="{.metadata.creationTimestamp}"`
echo "${PRJ}|${PRJ_DISPL_NAME}|${CRT_TS}|${PRJ_REQ}|${PRJ_MEM}" >> tmp_prj_info.txt
done



echo "PROJECT|DEPLOYMENT_CONFIG|DEPLOYMENT_CONFIG_VERSION|VOLUME_NAME|MOUNT_PATH|PVC_NAME|PVC_SIZE|PVC_CAPACITY_SIZE|PVC_ACCESS_MODE|PVC_STATE|PV_NAME|PV_CAPACITY|PV_NFS_SERVER|PF_NFS_PATH" >> tmp_dc_pv_info_$(date +'%d%b%Y').txt && \
echo "PROJECT|BUILD_CONFIG|BUILD_CONFIG_VERSION|BC_SRC_TYPE|BC_SRC_URI|BC_SRC_REF|BC_STRATEGY_TYPE|BC_SRC_STRATEGY_KIND|BC_SRC_STRATEGY_NS|BC_SRC_STRATEGY_NAME" >> tmp_bc_info_$(date +'%d%b%Y').txt && \
for PRJ in `oc get projects | awk '{print $1}' | egrep -v "NAME|management-infra|default|openshift|nvs-oam|nvs-rstudio-ide|logging|kube-system|cicd|nvs-shinys2i|solace|redmine|ocp-ops-view|nerecr" | sort`; do
    echo "======Project: $PRJ======="
    for DC in `oc get dc -n ${PRJ} -o custom-columns=NAME:.metadata.name | grep -v NAME`; do
      sleep 5 #to reduce the request rate
      echo "======DC: $DC======="
      DC_NAME=${DC}
      DC_VER=`oc get dc ${DC} -n ${PRJ} -o jsonpath="{.status.latestVersion}"`
      for VOL in `oc get dc ${DC} -n ${PRJ} -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\n"}{end}'`; do
        VOL_NAME=${VOL}
        PVC_NAME=`oc get dc ${DC} -n ${PRJ} -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"${VOL_NAME}\")].persistentVolumeClaim.claimName}"`
        if [ -n "$PVC_NAME" ] &&  [[ ! "$PVC_NAME" != "Error executing" ]]; then
            MNT_PATH=`oc get dc ${DC} -n ${PRJ} -o jsonpath="{.spec.template.spec.containers[].volumeMounts[?(@.name==\"${VOL_NAME}\")].mountPath}"` #we need a regex match here
            PVC_SIZE=`oc get pvc ${PVC_NAME} -o jsonpath='{.spec.resources.requests.storage}'`
            PV_NAME=`oc get pvc ${PVC_NAME} -o jsonpath='{.spec.volumeName}'`
            PVC_ACCESS_MODE=`oc get pvc ${PVC_NAME} -o jsonpath='{.spec.accessModes}'`
            PVC_CAPACITY_SIZE=`oc get pvc ${PVC_NAME} -o jsonpath='{.status.capacity.storage}'`
            PVC_STATE=`oc get pvc ${PVC_NAME} -o jsonpath='{.status.phase}'`
            PV_CAPACITY=`oc get pv ${PV_NAME} -o jsonpath="{.spec.capacity.storage}"`
            PV_NFS_SERVER=`oc get pv ${PV_NAME} -o jsonpath="{.spec.nfs.server}"`
            PV_NFS_PATH=`oc get pv ${PV_NAME} -o jsonpath="{.spec.nfs.path}"`
        else
            PVC_NAME="";MNT_PATH=""; PVC_SIZE=""; PV_NAME=""; PVC_ACCESS_MODE=""; PVC_CAPACITY_SIZE=""; PVC_STATE=""; PV_CAPACITY=""; PV_NFS_SERVER=""; PV_NFS_PATH=""
        fi
        echo "${PRJ}|${DC_NAME}|${DC_VER}|${VOL_NAME}|${MNT_PATH}|${PVC_NAME}|${PVC_SIZE}|${PVC_CAPACITY_SIZE}|${PVC_ACCESS_MODE}|$PVC_STATE|${PV_NAME}|${PV_CAPACITY}|${PV_NFS_SERVER}|${PV_NFS_PATH}" >> tmp_dc_pv_info_$(date +'%d%b%Y').txt
      done
    done
    if [[ `oc get bc -n ${PRJ}` != "" ]];then
      for BC in `oc get bc -n ${PRJ} -o custom-columns=NAME:.metadata.name | grep -v NAME`; do
          BC_NAME=${BC}
          BC_VER=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.status.lastVersion}"`
          BC_SOURCE_TYPE=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.source.type}"`
          
          if [ "$BC_SOURCE_TYPE" == "Git" ]; then
              BC_SOURCE_URI=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.source.git.uri}"`
              BC_SOURCE_REF=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.source.git.ref}"`
          else
              BC_SOURCE_URI="None"
              BC_SOURCE_REF="None"
          fi
 
          BC_STRATEGY_TYPE=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.strategy.type}"`
          BC_SRC_STRATEGY_FROM_KIND=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.strategy.sourceStrategy.from.kind}"`
          BC_SRC_STRATEGY_FROM_NS=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.strategy.sourceStrategy.from.namespace}"`
          BC_SRC_STRATEGY_FROM_NAME=`oc get bc ${BC} -n ${PRJ} -o jsonpath="{.spec.strategy.sourceStrategy.from.name}"`
          echo "${PRJ}|${BC_NAME}|${BC_VER}|${BC_SOURCE_TYPE}|${BC_SOURCE_URI}|${BC_SOURCE_REF}|${BC_STRATEGY_TYPE}|${BC_SRC_STRATEGY_FROM_KIND}|${BC_SRC_STRATEGY_FROM_NS}|${BC_SRC_STRATEGY_FROM_NAME}" >> tmp_bc_info_$(date +'%d%b%Y').txt
        done
    fi
done

