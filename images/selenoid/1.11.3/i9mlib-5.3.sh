#!/bin/bash

function start {
  emptyData=false
  firstStart=false
  changeNode=false

  if [[ ! -z "${STORAGE_SERVICE}" ]];then
    getCurNodeId
    curNode=$RET_VAL

    if [[ ! "${curNode}" =~ [a-z0-9]{24,26} ]]; then
      echo "[IMAGENARIUM]: Strange curNode name: ${curNode}. Exiting."
      sleep 5
      exit -1
    fi

    storeAndGet "curNode" $curNode
    prevNode=$RET_VAL

    getContainerId
    containerId=$RET_VAL

    getVolumes $containerId
    volumes=$RET_VAL

    echo "[IMAGENARIUM]: curNode: $curNode, prevNode: $prevNode"
    echo "[IMAGENARIUM]: current container id: $containerId"
    echo "[IMAGENARIUM]: detected volumes: $volumes"

    if [ -z "${prevNode}" ]; then
      firstStart=true
      if [ "${DELETE_DATA}" == "true" ]; then
        echo "[IMAGENARIUM]: First run. Remove stale data directory."
        deleteDirs "$volumes"
        emptyData=true
      fi
    else
      if [[ ! "${prevNode}" =~ [a-z0-9]{24,26} ]]; then
        echo "[IMAGENARIUM]: Strange prevNode name: ${prevNode}. Exiting."
        sleep 5
        exit -1
      fi

      if [[ $curNode != $prevNode ]]; then
        echo "[IMAGENARIUM]: Current nodeId($curNode) not equals previous nodeId($prevNode)."

        if [[ "${ALLOW_DELETE_DATA_IF_NODE_ID_CHANGE}" == "true" ]]; then
          echo "[IMAGENARIUM]: Remove stale data directory."

          deleteDirs "$volumes"
          emptyData=true
        fi

        changeNode=true
      fi
    fi
  fi

  : ${IMAGENARIUM_ADMIN_MODE="false"}

  export EMPTY_DATA=$emptyData
  export FIRST_START=$firstStart
  export CHANGE_NODE=$changeNode

  if [[ "${IMAGENARIUM_ADMIN_MODE}" == "false" ]]; then
    echo "[IMAGENARIUM]: Starting app in normal mode..."
    exec /run.sh $@
  else
    if [[ "${IMAGENARIUM_RUN_APP}" == "true" ]]; then
      echo "[IMAGENARIUM]: Starting app in admin mode..."

      /run.sh $@ &
      pid="$!"

      trap "echo '[Imagenarium]: Exiting shell. Terminate child process: ${pid}'; kill -15 ${pid}; wait ${pid}; exit 143" SIGTERM
      tail -f /dev/null & wait ${!}
    else
      echo "[IMAGENARIUM]: Running container without app..."

      trap "exit 143" SIGTERM
      tail -f /dev/null & wait ${!}
    fi
  fi
}

function getContainerId {
  RET_VAL=$(cat /proc/1/cgroup | grep "docker/" | tail -1 | sed "s/^.*\///" | cut -c 1-12)
}

function getCurNodeId {
  RET_VAL=$(curl --unix-socket /var/run/docker.sock -sX GET http://1.33/info | jq -r '.Swarm.NodeID')
}

function getCurNodeIp {
  RET_VAL=$(curl --unix-socket /var/run/docker.sock -sX GET http://1.33/info | jq -r '.Swarm.NodeAddr')
}

function getVolumes {
  containerId=$1
  selector=".Mounts[] | select(.Type == \"volume\") | .Destination"
  RET_VAL=$(curl -s --unix-socket /var/run/docker.sock -X GET http:/v1.33/containers/${containerId}/json | jq -r "${selector}" || true)
}

function deleteDirs {
  dirs=$1

  IFS=' ' read -ra DIRS <<< $(echo $dirs)

  for i in ${!DIRS[@]}; do
    if [[ ${DIRS[$i]} != *"docker.sock"* ]]; then
      echo "[IMAGENARIUM]: delete all data in dir: ${DIRS[$i]}"
      rm -rf ${DIRS[$i]}/*
    fi
  done
}

#==============Storage service=================================================

function storeAndGet {
  requestStorage "/put/${SERVICE_NAME}/$1?value=$2"
}

function findExternalIpByNodeId {
  nodeId=$1

  if [ -z ${nodeId} ]; then
    getCurNodeId
    nodeId=$RET_VAL
  fi

  requestStorage "/nodes/externalIp/node/${nodeId}"
}

function findExternalIpByServiceName {
  serviceName=$1

  : ${serviceName=${SERVICE_NAME}}

  requestStorage "/nodes/externalIp/service/${serviceName}"
}

function requestStorage {
  requestUrl=$1

  if [[ ! "${STORAGE_SERVICE}" ]]; then
    echo >&2 "[IMAGENARIUM]: You need to specify STORAGE_SERVICE"
    exit 0
  fi

  while true; do
    echo "[IMAGENARIUM]: Try to connect to storage service: ${STORAGE_SERVICE} with url: $requestUrl"

    : ${STORAGE_PORT:=8080}

    RET_VAL=$(curl -fX GET http://$STORAGE_SERVICE:${STORAGE_PORT}${requestUrl} 2>/dev/null)

    status=$?

    if [ $status -ne 0 ]; then
      echo "[IMAGENARIUM]: Can't connect to storage service..."
    else
      echo "[IMAGENARIUM]: Response from storage service: $RET_VAL"
      break
    fi

    sleep 3
  done
}

function mountNfs {
  mnt_path=$1
  mnt_server=$2
  mnt_port=$3

  if [[ ! "${mnt_port}" ]]; then
    mnt_port="2049"
  fi

  while true; do
    echo "[IMAGENARIUM]: Trying to mount file storage NFS directory ${mnt_path} from ${mnt_server}"

    [ -d ${mnt_path} ] || mkdir -p ${mnt_path}

    mount -v -o port=${mnt_port},vers=4,loud,sync,retrans=0 ${mnt_server}:/ ${mnt_path}

    status=$?

    if [ "${status}" == "0" ]; then
      echo "[IMAGENARIUM]: Mount successful"
      break
    fi

    sleep 3
  done
}

function findIp {
  networkName=$1

  if [[ ! "${networkName}" ]]; then
    networkName="host"
  fi

  while true; do
    echo "[IMAGENARIUM]: try to resolve current ip address in $networkName..."

    if [[ "${networkName}" == "host" ]]; then
      getCurNodeIp
      ip=$RET_VAL
    else
      ip=$(curl --unix-socket /var/run/docker.sock -g -sX GET "http:/v1.32/containers/json?filters={\"name\":[\"^/${PARENT_CONTAINER_NAME:-$CONTAINER_NAME}$\"]}" | jq .[0].NetworkSettings.Networks.\"$networkName\".IPAddress | tr -d '"')
    fi

    if [[ $ip != "null" ]]; then
      echo "[IMAGENARIUM]: Found ip address in $networkName: ${ip}"
      RET_VAL=$ip
      break
    fi

    sleep 1
  done
}

#================Multicast===================================================

function findInterfaceByIp {
  RET_VAL=$(ip addr show | grep "inet $1" | awk '{print $NF}')
}

function findIpByInterface {
  RET_VAL=$(ip addr show $1 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
}

function addMulticastRoute {
  route add -net 224.0.0.0 netmask 240.0.0.0 $1
  echo "[IMAGENARIUM]: Route successfully added: $(route | grep 224.0.0.0)"
}

#============================================================================

function waitPids {
  IFS=' ' read -ra pidArray <<< "$@"

  pids="$@"

  trap "echo '[Imagenarium]: Exiting shell. Terminate child processes: ${pids}'; kill -15 ${pids}" SIGTERM SIGINT

  for pid in "${pidArray[@]}"; do
    wait "${pid}"
    echo "Process with pid ${pid} exited"
  done
}

function waitPort {
  port=$1

  while true; do
    echo "[IMAGENARIUM]: Checking TCP status for: ${port}"

    nc -zw3 127.0.0.1 $port

    status=$?

    if [ "$status" == "0" ]; then
      echo "[IMAGENARIUM]: Success"
      break
    fi

    sleep 1
  done
}

function waitHost {
  while ! host $1; do
    echo >&2 "[IMAGENARIUM]: Waiting for resolve hostname: $1"
    sleep 3
  done
}

function setHostname {
  echo "$(hostname -i) ${SERVICE_NAME}" >> /etc/hosts

  sed "/${HOSTNAME}*/d" /etc/hosts > /tmp/hosts.new
  cat /tmp/hosts.new > /etc/hosts

  hostname ${SERVICE_NAME}

  echo ${SERVICE_NAME} > /etc/hostname

  export HOSTNAME=${SERVICE_NAME}
}
