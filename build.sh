#!/usr/bin/env bash

set -e

# 所有构建路径以脚本所在仓库为锚，不依赖调用目录。
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_PATH="$REPO_ROOT/wrt_core"

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
    echo "       $0"
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

BASE_CONFIG_FILE="$BASE_PATH/deconfig/common/compile_base.config"
CONFIG_FRAGMENT_DIR="$BASE_PATH/deconfig/fragments"
DEFAULT_CONFIG_FRAGMENTS=()
ADD_CONFIG_FRAGMENT_LIST=()
REMOVE_CONFIG_FRAGMENT_LIST=()
EFFECTIVE_CONFIG_FRAGMENTS=()

source "$BASE_PATH/modules/lib/common.sh"
source "$BASE_PATH/modules/config.sh"
source "$BASE_PATH/modules/container_build.sh"
source "$BASE_PATH/modules/post_config_fixes.sh"
if [[ ! -f "$BASE_CONFIG_FILE" ]]; then
    echo "Base config not found: $BASE_CONFIG_FILE" >&2
    exit 1
fi

if [[ $Build_Mod == "container" ]]; then
    run_container_build ""
    exit 0
fi

if [[ $Build_Mod == "container_debug" ]]; then
    run_container_build "debug"
    exit 0
fi

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

if [[ -d "$REPO_ROOT/action_build" ]]; then
    # GitHub Actions 使用 action_build 作为固定构建目录。
    BUILD_DIR="action_build"
fi
if [[ -z "$BUILD_DIR" ]]; then
    echo "BUILD_DIR is not configured in $INI_FILE" >&2
    exit 1
fi
BUILD_ROOT="$BUILD_DIR"
[[ "$BUILD_ROOT" == /* ]] || BUILD_ROOT="$REPO_ROOT/$BUILD_ROOT"

"$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_ROOT" "$COMMIT_HASH"

apply_config
print_config_fragment_summary
remove_uhttpd_dependency

cd "$BUILD_ROOT"
make defconfig

sync_x86_64_distfeeds

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BUILD_ROOT/bin/targets"
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
