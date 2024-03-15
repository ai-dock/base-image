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
    # Beware: If you copied files at buildtime without setting gid 1111 the fs will bloat
    # COPYs should ensure local permissions are suitable first
    printf "Fixing container file permissions...\n"
    chown root.ai-dock /opt
    chmod g+w /opt
    chmod g+s /opt
    find /opt -type d ! -perm -g=s -exec chmod g+s {} \;
    find /opt -type d ! -perm -g=w -exec chmod g+w {} \;
    # See above - Remember this is overlayfs so touch as little as possible
    find /opt -not -group ai-dock -exec chown root.ai-dock {} \;
    chown -R root.root /root
    printf "Container file permissions reset\n"
}

function fix_workspace() {
    if [[ $WORKSPACE_MOUNTED == "true" && $WORKSPACE_PERMISSIONS != "false" ]]; then
        printf "Fixing workspace permissions...\n"
        chown "${WORKSPACE_UID}.${WORKSPACE_GID}" "${WORKSPACE}"
        chmod g+w "${WORKSPACE}"
        chmod g+s "${WORKSPACE}"
        find "${WORKSPACE}" -type d ! -perm -g=s -exec chmod g+s {} \;
        find "${WORKSPACE}" ! -uid "${WORKSPACE_UID}" -exec chown "${WORKSPACE_UID}.${WORKSPACE_GID}" {} \;
        chmod o-rw "${WORKSPACE}/home/${USER_NAME}"
        if [[ -e ${WORKSPACE}/home/user/.ssh/authorized_keys ]]; then
            chmod 700 "${WORKSPACE}/home/${USER_NAME}/.ssh"
            chmod 600 "${WORKSPACE}/home/${USER_NAME}/.ssh/authorized_keys"
        fi
        printf "Workspace file permissions reset\n"
    else
        printf "Workspace permissions not changed (no mount/non-standard fs)\n"
    fi
}

main "$@"