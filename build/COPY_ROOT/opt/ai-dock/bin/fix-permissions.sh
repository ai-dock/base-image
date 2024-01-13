#!/bin/bash

function main() {
  while getopts o: flag; do
      case "${flag}" in
          o) only="${OPTARG}"
      esac
  done
  
  if [[ ${only,,} == "container" ]]; then
      fix_container
  elif [[ ${only,,} == "workspace" ]]; then
      fix_workspace
  else
      fix_container
      fix_workspace
  fi
}

function fix_container() {
    chown -R root.ai-dock /opt
    chmod -R g+s /opt
    chmod -R ug+rwX /opt
    setfacl -R -d -m g:ai-dock:rwx /opt
    setfacl -R -d -m m:rwx /opt
}

function fix_workspace() {
    printf "Fixing workspace permissions...\n"
    chown -R ${WORKSPACE_UID}.${WORKSPACE_GID} "${WORKSPACE}"
    chmod -R g+s ${WORKSPACE}
    setfacl -R -d -m u:"${WORKSPACE_UID}":rwx "${WORKSPACE}"
    setfacl -R -d -m m:rwx "${WORKSPACE}"
    chmod o-rw ${WORKSPACE}/home/user
    if [[ -e ${WORKSPACE}/home/user/.ssh/authorized_keys ]]; then
        chmod 700 ${WORKSPACE}/home/user/.ssh
        chmod 600 ${WORKSPACE}/home/user/.ssh/authorized_keys
    fi
}

main "$@"