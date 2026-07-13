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
    echo "Usage: $0 <device> [debug|container|container_debug|config_preview]"
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
        echo "  5) config_preview"
        printf "Select build mode (1-5, q to quit): "

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
            Build_Mod="config_preview"
            return
        fi

        echo "Invalid selection. Please enter 1, 2, 3, 4, or 5."
    done
}

is_interactive_terminal() {
    [[ -t 0 && -t 1 ]]
}

validate_build_mode() {
    case "$Build_Mod" in
        ""|debug|container|container_debug|config_preview)
            return 0
            ;;
        *)
            echo "Error: unsupported build mode: $Build_Mod" >&2
            print_usage >&2
            exit 1
            ;;
    esac
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

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

validate_build_mode

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

CONFIG_FRAGMENT_DIR="$BASE_PATH/deconfig/fragments"
DEFAULT_CONFIG_FRAGMENTS=()
ADD_CONFIG_FRAGMENT_LIST=()
REMOVE_CONFIG_FRAGMENT_LIST=()
EFFECTIVE_CONFIG_FRAGMENTS=()

parse_fragment_csv() {
    local csv=$1
    local output_array=$2
    local item
    local -n target_array="$output_array"

    target_array=()
    csv=${csv//[[:space:]]/}
    [[ -n $csv ]] || return 0

    IFS=',' read -r -a target_array <<< "$csv"
    for item in "${target_array[@]}"; do
        if [[ -z $item ]]; then
            echo "Error: empty config fragment name in '$csv'." >&2
            exit 1
        fi

        if [[ ! $item =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            echo "Error: invalid config fragment name '$item'." >&2
            exit 1
        fi
    done
}

fragment_in_list() {
    local fragment=$1
    shift
    local item

    for item in "$@"; do
        [[ $item == "$fragment" ]] && return 0
    done

    return 1
}

append_unique_fragment() {
    local fragment=$1
    local output_array=$2
    local -n target_array="$output_array"

    fragment_in_list "$fragment" "${target_array[@]}" && return 0
    target_array+=("$fragment")
}

validate_enable_fragment() {
    local fragment=$1
    local fragment_path="$CONFIG_FRAGMENT_DIR/$fragment.config"

    if [[ ! -f $fragment_path ]]; then
        echo "Error: config fragment not found: $fragment_path" >&2
        exit 1
    fi
}

join_fragments() {
    local IFS=','
    echo "$*"
}

resolve_config_fragments() {
    local fragment
    local candidate_fragments=()

    parse_fragment_csv "$(read_ini_by_key "CONFIG_FRAGMENTS")" DEFAULT_CONFIG_FRAGMENTS
    parse_fragment_csv "${ADD_CONFIG_FRAGMENTS:-}" ADD_CONFIG_FRAGMENT_LIST
    parse_fragment_csv "${REMOVE_CONFIG_FRAGMENTS:-}" REMOVE_CONFIG_FRAGMENT_LIST

    for fragment in "${DEFAULT_CONFIG_FRAGMENTS[@]}" "${ADD_CONFIG_FRAGMENT_LIST[@]}" "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; do
        validate_enable_fragment "$fragment"
    done

    for fragment in "${DEFAULT_CONFIG_FRAGMENTS[@]}" "${ADD_CONFIG_FRAGMENT_LIST[@]}"; do
        append_unique_fragment "$fragment" candidate_fragments
    done

    EFFECTIVE_CONFIG_FRAGMENTS=()
    for fragment in "${candidate_fragments[@]}"; do
        if ! fragment_in_list "$fragment" "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; then
            EFFECTIVE_CONFIG_FRAGMENTS+=("$fragment")
        fi
    done

    for fragment in "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; do
        if [[ $fragment == "nss" ]]; then
            echo "Warning: removing platform fragment 'nss' is high risk." >&2
        fi
    done
}

print_config_fragment_summary() {
    echo "Config fragments:"
    echo "  Device: $Dev"
    echo "  Default fragments: $(join_fragments "${DEFAULT_CONFIG_FRAGMENTS[@]}")"
    echo "  Add fragments: $(join_fragments "${ADD_CONFIG_FRAGMENT_LIST[@]}")"
    echo "  Remove fragments: $(join_fragments "${REMOVE_CONFIG_FRAGMENT_LIST[@]}")"
    echo "  Effective fragments: $(join_fragments "${EFFECTIVE_CONFIG_FRAGMENTS[@]}")"
}

print_config_preview() {
    print_config_fragment_summary
    echo "Config assembly order:"
    echo "  1) $CONFIG_FILE"
    echo "  2) $BASE_PATH/deconfig/compile_base.config"

    local order=3
    local fragment
    for fragment in "${EFFECTIVE_CONFIG_FRAGMENTS[@]}"; do
        echo "  $order) $CONFIG_FRAGMENT_DIR/$fragment.config"
        order=$((order + 1))
    done

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
        -e ADD_CONFIG_FRAGMENTS \
        -e REMOVE_CONFIG_FRAGMENTS \
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
    local fragment

    \cp -f "$CONFIG_FILE" "$BASE_PATH/../$BUILD_DIR/.config"

    cat "$BASE_PATH/deconfig/compile_base.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    for fragment in "${EFFECTIVE_CONFIG_FRAGMENTS[@]}"; do
        cat "$CONFIG_FRAGMENT_DIR/$fragment.config" >> "$BASE_PATH/../$BUILD_DIR/.config"
    done

}

# 读取设备元信息，确定上游源码和构建目录。
REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

resolve_config_fragments

if [[ $Build_Mod == "config_preview" ]]; then
    print_config_preview
    exit 0
fi

if [[ -d action_build ]]; then
    # GitHub Actions 使用 action_build 作为固定构建目录。
    BUILD_DIR="action_build"
fi

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE" 2>/dev/null; then
    export WRT_IS_X86_64=1
fi

"$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_DIR" "$COMMIT_HASH"

apply_config
print_config_fragment_summary
remove_uhttpd_dependency

cd "$BASE_PATH/../$BUILD_DIR"
make defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/../$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

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
