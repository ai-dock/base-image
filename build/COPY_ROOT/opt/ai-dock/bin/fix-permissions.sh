#!/bin/bash

function main() {
  while getopts o: flag; do
      case "${flag}" in
          o) only="${OPTARG}"
      esac
  done
  
  fix_workspace
}

function fix_workspace() {
    if [[ $WORKSPACE_PERMISSIONS == "true" ]]; then
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
    else
        printf "No permissions changed (non-standard fs)\n"
    fi
}

main "$@"