#!/usr/bin/env bash

set -e

Dev=$1
Build_Mod=$2

resolve_build_dir() {
    local script_dir
    local repo_root
    local wrt_core_path
    local ini_file
    local build_dir

    script_dir=$(cd "$(dirname "$0")" && pwd)

    if [ -d "$script_dir/compilecfg" ]; then
        wrt_core_path="$script_dir"
        repo_root=$(cd "$script_dir/.." && pwd)
    elif [ -d "$script_dir/wrt_core/compilecfg" ]; then
        wrt_core_path="$script_dir/wrt_core"
        repo_root="$script_dir"
    elif [ -d "$script_dir/../wrt_core/compilecfg" ]; then
        wrt_core_path="$script_dir/../wrt_core"
        repo_root=$(cd "$script_dir/.." && pwd)
    else
        echo "Error: wrt_core directory not found!" >&2
        return 1
    fi

    ini_file="$wrt_core_path/compilecfg/$Dev.ini"
    if [[ ! -f "$ini_file" ]]; then
        echo "Error: INI file not found: $ini_file" >&2
        return 1
    fi

    build_dir=$(awk -F"=" '$1 == "BUILD_DIR" {print $2; exit}' "$ini_file")
    if [[ -z "$build_dir" ]]; then
        echo "Error: BUILD_DIR is not configured in $ini_file" >&2
        return 1
    fi

    if [[ -d "$repo_root/action_build" ]]; then
        build_dir="action_build"
    fi

    printf '%s\n' "$repo_root/$build_dir"
}

if [ -z "$Dev" ]; then
    echo "Usage: $0 <dev_name> [debug]"
    echo "或者运行 ./start.sh 进行交互式选择"
    exit 1
fi

if [[ $Build_Mod == "debug" ]]; then
    echo "[container] running inside $(hostname) as $(whoami) in $(pwd)"
    ./build.sh "$Dev" debug
    BUILD_WORKDIR=$(resolve_build_dir)
    cd "$BUILD_WORKDIR"
    export PS1='(wrt-container-debug) \u@\h \w\\$ '
    exec bash -i
fi

LOGFILE="build-$Dev-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
set -x
echo "[container] running inside $(hostname) as $(whoami) in $(pwd)"

./build.sh "$Dev"
