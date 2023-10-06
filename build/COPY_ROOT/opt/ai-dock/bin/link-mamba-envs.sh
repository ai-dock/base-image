#!/bin/bash

printf "Linking mamba environments to /opt...\n"

for item in ${WORKSPACE}micromamba/*; do
    if [[ $item = "${WORKSPACE}micromamba/envs" ]]; then
        # Preventing duplicate envs
        for  env in ${WORKSPACE}micromamba/envs/*; do
            env_name="$(basename $env)"
            o_path="/opt/micromamba/envs/${env_name}"
            w_path="${WORKSPACE}micromamba/envs/${env_name}"
            mkdir -p "$o_path"
            for dir in ${w_path}/*; do
              dir_name="$(basename $dir)"
              ln -sf ${w_path}/${dir_name} ${o_path}/${dir_name}
            done
        done
    else
        item_name="$(basename $item)"
        o_path="/opt/micromamba/${item_name}"
        w_path="${WORKSPACE}micromamba/${item_name}"
        ln -sf ${w_path} ${o_path}
    fi
done