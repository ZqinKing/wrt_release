#!/usr/bin/env bash

set -e

# 定位 wrt_core，兼容仓库根目录或上级目录调用。
if [ -d "wrt_core" ]; then
    WRT_CORE_PATH="wrt_core"
elif [ -d "../wrt_core" ]; then
    WRT_CORE_PATH="../wrt_core"
else
    echo "Error: wrt_core directory not found!"
    exit 1
fi

BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)

REPO_ROOT=$(cd "$BASE_PATH/.." && pwd)

Dev=$1
Build_Mod=$2

SUPPORTED_DEVS=()

# 只有 compilecfg 与 deconfig 同名成对存在的设备才可构建。
collect_supported_devs() {
    local ini_file
    local dev_key
    local IFS

    SUPPORTED_DEVS=()

    for ini_file in "$BASE_PATH"/compilecfg/*.ini; do
        [[ -f "$ini_file" ]] || continue

        dev_key=$(basename "$ini_file" .ini)
        if [[ -f "$BASE_PATH/deconfig/$dev_key.config" ]]; then
            SUPPORTED_DEVS+=("$dev_key")
        fi
    done

    if [[ ${#SUPPORTED_DEVS[@]} -eq 0 ]]; then
        return
    fi

    IFS=$'\n' SUPPORTED_DEVS=($(printf '%s\n' "${SUPPORTED_DEVS[@]}" | LC_ALL=C sort))
}

print_usage() {
    echo "Usage: $0 <device> [debug|container|container_debug|recipe_preview|recipe_config]"
    echo "       ./start.sh"
}

print_supported_devs() {
    local index

    echo "Supported devices:"
    for ((index = 0; index < ${#SUPPORTED_DEVS[@]}; index++)); do
        printf "  %d) %s\n" "$((index + 1))" "${SUPPORTED_DEVS[index]}"
    done
}

prompt_select_dev() {
    local input
    local selected_index

    while true; do
        print_supported_devs
        printf "Select device by number (q to quit): "

        if ! read -r input; then
            echo
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*[qQ][[:space:]]*$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            selected_index=${BASH_REMATCH[1]}
            if ((selected_index >= 1 && selected_index <= ${#SUPPORTED_DEVS[@]})); then
                Dev=${SUPPORTED_DEVS[selected_index - 1]}
                return
            fi
        fi

        echo "Invalid selection. Please enter a number between 1 and ${#SUPPORTED_DEVS[@]}."
    done
}

prompt_select_build_mode() {
    local input

    while true; do
        echo "Build mode:"
        echo "  1) normal"
        echo "  2) debug"
        echo "  3) container"
        echo "  4) container_debug"
        echo "  5) recipe_config"
        echo "  6) recipe_preview"
        printf "Select build mode (1-6, q to quit): "

        if ! read -r input; then
            echo
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*[qQ][[:space:]]*$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        if [[ "$input" =~ ^[[:space:]]*1[[:space:]]*$ ]]; then
            Build_Mod=""
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*2[[:space:]]*$ ]]; then
            Build_Mod="debug"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*3[[:space:]]*$ ]]; then
            Build_Mod="container"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*4[[:space:]]*$ ]]; then
            Build_Mod="container_debug"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*5[[:space:]]*$ ]]; then
            Build_Mod="recipe_config"
            return
        fi

        if [[ "$input" =~ ^[[:space:]]*6[[:space:]]*$ ]]; then
            Build_Mod="recipe_preview"
            return
        fi

        echo "Invalid selection. Please enter 1, 2, 3, 4, 5, or 6."
    done
}

is_interactive_terminal() {
    [[ -t 0 && -t 1 ]]
}

if [[ $# -eq 0 ]]; then
    collect_supported_devs

    if [[ ${#SUPPORTED_DEVS[@]} -eq 0 ]]; then
        echo "Error: no supported devices found."
        exit 1
    fi

    if ! is_interactive_terminal; then
        print_usage
        print_supported_devs
        exit 1
    fi

    prompt_select_dev

    if [[ -z $Build_Mod ]]; then
        prompt_select_build_mode
    fi
fi

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"


if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

read_ini_by_key_from_file() {
    local file=$1
    local key=$2
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$file"
}


resolve_config_file() {
    local base_config
    base_config=$(read_ini_by_key "BASE_CONFIG")

    if [[ -n "$base_config" ]]; then
        if [[ "$base_config" = /* ]]; then
            CONFIG_FILE="$base_config"
        else
            CONFIG_FILE="$BASE_PATH/$base_config"
        fi
    fi
}

resolve_config_file
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

append_config_fragment() {
    local fragment=$1
    local fragment_path

    if [[ "$fragment" = /* ]]; then
        fragment_path="$fragment"
    else
        fragment_path="$BASE_PATH/$fragment"
    fi

    if [[ ! -f "$fragment_path" ]]; then
        echo "Config fragment not found: $fragment_path" >&2
        exit 1
    fi

    cat "$fragment_path" >> "$BASE_PATH/../$BUILD_DIR/.config"
}

apply_target_config_fragments() {
    local fragments
    local old_ifs
    local fragment

    fragments=$(read_ini_by_key "CONFIG_FRAGMENTS")
    [[ -n "$fragments" ]] || return 0

    old_ifs="$IFS"
    IFS=','
    for fragment in $fragments; do
        fragment="${fragment#${fragment%%[![:space:]]*}}"
        fragment="${fragment%${fragment##*[![:space:]]}}"
        [[ -n "$fragment" ]] || continue
        append_config_fragment "$fragment"
    done
    IFS="$old_ifs"
}

run_build_recipe_phase() {
    local phase=$1
    BASE_PATH="$BASE_PATH" source "$BASE_PATH/recipe.sh"
    recipe_init "$Dev" "$INI_FILE" "$BASE_PATH/../$BUILD_DIR" "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH"
    recipe_run_phase "$phase"
}
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
    cat > "$container_tmp_Dockerfile" <<EOF
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
        --shm-size=8g \
        --ipc=shareable \
        --ulimit nofile=65535:65535 \
        "$container_name" \
        bash wrt_core/build_container.sh "$Dev" "$container_build_mod"
}

remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/../$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/../$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

if [[ $Build_Mod == "container" ]]; then
    run_container_build ""
    exit 0
fi

if [[ $Build_Mod == "container_debug" ]]; then
    run_container_build "debug"
    exit 0
fi

apply_config() {
    resolve_config_file
    \cp -f "$CONFIG_FILE" "$BASE_PATH/../$BUILD_DIR/.config"

    if grep -qE "(ipq60xx|ipq807x)" "$BASE_PATH/../$BUILD_DIR/.config" &&
        ! grep -q "CONFIG_GIT_MIRROR" "$BASE_PATH/../$BUILD_DIR/.config"; then
        cat "$BASE_PATH/deconfig/nss.config" >> "$BASE_PATH/../$BUILD_DIR/.config"
    fi

    cat "$BASE_PATH/deconfig/compile_base.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    cat "$BASE_PATH/deconfig/docker_deps.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    cat "$BASE_PATH/deconfig/proxy.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    apply_target_config_fragments
}

# 读取设备元信息，确定上游源码和构建目录。
REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

if [[ -d action_build ]]; then
    # GitHub Actions 使用 action_build 作为固定构建目录。
    BUILD_DIR="action_build"
fi
if [[ $Build_Mod == "recipe_preview" || $Build_Mod == "recipe_config" ]]; then
    BASE_PATH="$BASE_PATH" source "$BASE_PATH/recipe.sh"
    recipe_allow_conflicts=0
    if [[ $Build_Mod == "recipe_config" ]]; then
        recipe_allow_conflicts=1
    fi
    recipe_init "$Dev" "$INI_FILE" "$BASE_PATH/../$BUILD_DIR" "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH" "$recipe_allow_conflicts"
    if [[ $Build_Mod == "recipe_config" ]]; then
        BASE_PATH="$BASE_PATH" source "$BASE_PATH/modules/recipe_edit.sh"
        recipe_open_config_cli
    else
        recipe_print_plan
    fi
    exit 0
fi


"$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_DIR" "$COMMIT_HASH" "$Dev" "$INI_FILE"

apply_config
run_build_recipe_phase pre_defconfig
remove_uhttpd_dependency

cd "$BASE_PATH/../$BUILD_DIR"
make defconfig
run_build_recipe_phase post_defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/../$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi
run_build_recipe_phase finalize

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/../$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec rm -f {} +
fi

make download -j$(($(nproc) * 2))
make -j$(($(nproc) + 1)) || make -j1 V=s

FIRMWARE_DIR="$BASE_PATH/../firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
\rm -f "$BASE_PATH/../firmware/Packages.manifest" 2>/dev/null

if [[ -d action_build ]]; then
    make clean
fi
