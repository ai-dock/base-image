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
    # Ensure we only affect files in this fs layer
    chown root.ai-dock /opt
    chmod g+s /opt
    find /opt -not -group ai-dock -exec chown root.ai-dock {} \;
    find /opt -type d ! -perm -g=w -exec chmod g+w {} \; -exec chmod g+s {} \;
}

function fix_workspace() {
    if [[ $WORKSPACE_PERMISSIONS == "true" ]]; then
        printf "Fixing workspace permissions...\n"
        chown "${WORKSPACE_UID}.${WORKSPACE_GID}" "${WORKSPACE}"
        chmod -R g+s "${WORKSPACE}"
        find "${WORKSPACE}" -not -group "${WORKSPACE_GID}" -exec chown "${WORKSPACE_UID}.${WORKSPACE_GID}" {} \;
        find "${WORKSPACE}" -type d ! -perm -g=w -exec chmod g+w {} \; -exec chmod g+s {} \;
        chmod o-rw "${WORKSPACE}/home/${USER_NAME}"
        if [[ -e ${WORKSPACE}/home/user/.ssh/authorized_keys ]]; then
            chmod 700 "${WORKSPACE}/home/${USER_NAME}/.ssh"
            chmod 600 "${WORKSPACE}/home/${USER_NAME}/.ssh/authorized_keys"
        fi
    else
        printf "No permissions changed (non-standard fs)\n"
    fi
}

main "$@"