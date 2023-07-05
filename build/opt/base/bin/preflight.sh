#!/bin/bash

# Extended image should have preflight.sh in $PATH before this one to modify startup behavior

printf "micromamba activate %s\n" $MAMBA_BASE_ENV >> /root/.bashrc
