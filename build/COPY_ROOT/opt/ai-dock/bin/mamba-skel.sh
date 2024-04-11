#!/bin/bash

env_location=$(micromamba info | grep "env location" | awk '{print $4}')

if [[ -z $env_location || $env_location == "-" ]]; then
    printf "This command must be run in a micromamba environment\n"
    exit 1
fi

activate_dir="${env_location}/etc/conda/activate.d"
deactivate_dir="${env_location}/etc/conda/deactivate.d"

mkdir -p "${activate_dir}"
mkdir -p "${deactivate_dir}"

# Default activation script

cat <<EOF > "${activate_dir}/10_ld.sh"
#!/bin/bash

export SYS_LD_LIBRARY_PATH="\${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="${env_location}/lib\${SYS_LD_LIBRARY_PATH:+:\${SYS_LD_LIBRARY_PATH}}"

EOF

# Default deactivation script
cat <<EOF > "${deactivate_dir}/90_ld.sh"
#!/bin/bash

export LD_LIBRARY_PATH="\${SYS_LD_LIBRARY_PATH}"

EOF
