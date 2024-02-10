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
    printf "Fixing container file permissions...\n"
    chown root.ai-dock /opt
    chmod g+s /opt
    find /opt -not -group ai-dock -exec chown root.ai-dock {} \;
    find /opt -type d ! -perm -g=s -exec chmod g+s {} \;
    find /opt ! -perm -g=w -exec chmod g+w {} \;
    printf "Container file permissions reset\n"
}

function fix_workspace() {
    if [[ $WORKSPACE_PERMISSIONS != "false" ]]; then
        printf "Fixing workspace permissions...\n"
        chown "${WORKSPACE_UID}.${WORKSPACE_GID}" "${WORKSPACE}"
        chmod -R g+s "${WORKSPACE}"
        find "${WORKSPACE}" -not -user "${WORKSPACE_UID}" -exec chown "${WORKSPACE_UID}.${WORKSPACE_GID}" {} \;
        find "${WORKSPACE}" -type d ! -perm -g=s -exec chmod g+s {} \;
        find "${WORKSPACE}" ! -perm -g=w -exec chmod g+w {} \;
        chmod o-rw "${WORKSPACE}/home/${USER_NAME}"
        if [[ -e ${WORKSPACE}/home/user/.ssh/authorized_keys ]]; then
            chmod 700 "${WORKSPACE}/home/${USER_NAME}/.ssh"
            chmod 600 "${WORKSPACE}/home/${USER_NAME}/.ssh/authorized_keys"
        fi
        printf printf "Workspace file permissions reset\n"
    else
        printf "Workspace permissions not changed (non-standard fs)\n"
    fi
}

main "$@"