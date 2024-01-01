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
    printf "Fixing container permissions...\n"
    items=micromamba:$OPT_SYNC
    IFS=: read -r -d '' -a path_array < <(printf '%s:\0' "$items")
    for item in "${path_array[@]}"; do
        if [[ -n $item ]]; then
            opt_dir="/opt/${item}"
            chown -R root.users "$opt_dir"
            chmod -R g+s "$opt_dir"
            chmod -R ug+rw "$opt_dir"
            setfacl -R -d -m g:users:rwx "$opt_dir"
            setfacl -R -d -m m:rwx "$opt_dir"
        fi
    done
    
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