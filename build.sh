#!/usr/bin/env bash

set -e

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1
Build_Mod=$2

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

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

if [[ -d $BASE_PATH/action_build ]]; then
    BUILD_DIR="action_build"
fi

$BASE_PATH/update.sh "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH"

\cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"

# cd "$BASE_PATH/$BUILD_DIR"
# make defconfig

# if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
#     DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
#     if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
#         sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
#     fi
# fi

# if [[ $Build_Mod == "debug" ]]; then
#     exit 0
# fi

# TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
# if [[ -d $TARGET_DIR ]]; then
#     find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec rm -f {} +
# fi

# make download -j$(($(nproc) * 2))
# make -j$(($(nproc) + 1)) || make -j1 V=s

# FIRMWARE_DIR="$BASE_PATH/firmware"
# \rm -rf "$FIRMWARE_DIR"
# mkdir -p "$FIRMWARE_DIR"
# find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
# \rm -f "$BASE_PATH/firmware/Packages.manifest" 2>/dev/null

# if [[ -d $BASE_PATH/action_build ]]; then
#     make clean
# fi
