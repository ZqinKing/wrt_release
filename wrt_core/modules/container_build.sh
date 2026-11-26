#!/usr/bin/env bash
# 主机构建容器的镜像准备与启动；与固件内 Docker 修正分离。

prepare_container_image() {
    local base_image=$1
    local image_name=$2
    local container_tmp_Dockerfile
    local container_default_user
    container_tmp_Dockerfile=$(mktemp Dockerfile.XXXXXX)
    cleanup_container_dockerfile() {
        rm -f "$container_tmp_Dockerfile"
    }
    trap cleanup_container_dockerfile RETURN
    docker pull "$base_image"
    container_default_user=$(docker run --rm "$base_image" whoami)
    cat >"$container_tmp_Dockerfile" <<EOF
FROM $base_image
USER root
RUN apt-get update && apt-get install -y sudo git jq build-essential cmake g++ clang bison flex libelf-dev libncurses5-dev python3-distutils zlib1g-dev python3 pkg-config libssl-dev
USER $container_default_user
RUN git config --global pull.rebase false
RUN git config --global advice.detachedHead false
CMD ["bash", "wrt_core/build_container.sh", "$image_name"]
EOF
    docker build -t "$image_name" -f "$container_tmp_Dockerfile" .
}

run_container_build() {
    local container_build_mod=$1
    local build_target_sdk
    local container_name
    build_target_sdk=$(read_ini_by_key "BUILD_TARGET_SDK")
    if [[ -z "$build_target_sdk" ]]; then
        echo "BUILD_TARGET_SDK not specified in $INI_FILE. Using default: openwrt-25.12"
        build_target_sdk="immortalwrt/sdk:openwrt-25.12"
    fi
    container_name="$(echo "$Dev" | tr '[:upper:]' '[:lower:]' | tr '/:' '-_')-build-container"
    prepare_container_image "$build_target_sdk" "$container_name"
    docker run --rm -it \
        -v "$REPO_ROOT":/build \
        -w /build \
        -e ADD_CONFIG_FRAGMENTS \
        -e REMOVE_CONFIG_FRAGMENTS \
        --shm-size=8g \
        --ipc=shareable \
        --ulimit nofile=65535:65535 \
        "$container_name" \
        bash wrt_core/build_container.sh "$Dev" "$container_build_mod"
}
