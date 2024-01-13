#!/bin/false

if [[ -z $ROCM_VERSION ]]; then
    printf "No valid ROCM_VERSION specified\n" >&2
    exit 1
fi

export ROCM_VERSION="$ROCM_VERSION"
env-store ROCM_VERSION
export ROCM_LEVEL="$ROCM_LEVEL"
env-store ROCM_LEVEL
export PATH=/opt/rocm/bin:$PATH
env-store PATH

curl -Ss https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} jammy main" \
    | tee --append /etc/apt/sources.list.d/rocm.list
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | tee /etc/apt/preferences.d/rocm-pin-600

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/${ROCM_VERSION}/ubuntu jammy main" \
    | tee --append /etc/apt/sources.list.d/rocm.list

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/${ROCM_VERSION}/ubuntu jammy proprietary" \
    | tee --append /etc/apt/sources.list.d/rocm.list

apt-get update

if [[ "${ROCM_LEVEL}" == "core" ]]; then
    $APT_INSTALL rocm-core \
                 rocm-opencl-runtime

elif [[ "${ROCM_LEVEL}" == "runtime" ]]; then
    $APT_INSTALL rocm-dev

elif [[ "${ROCM_LEVEL}" == "devel" ]]; then
    $APT_INSTALL rocm-libs \
                 rocm-opencl-sdk \
                 rocm-hip-sdk \
                 rocm-ml-sdk

else
    printf "No valid ROCM_LEVEL specified\n" >&2
    exit 1
fi
