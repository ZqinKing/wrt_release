#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)
source "$BASE_PATH/modules/lib/common.sh"
source "$BASE_PATH/modules/lib/network.sh"
REPO_ROOT=$(get_repo_root)

Dev=$1

INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
# GitHub Actions 使用仓库根目录下的固定源码目录。
BUILD_DIR="$REPO_ROOT/action_build"

echo $REPO_URL $REPO_BRANCH
# cache key 的 repo_flag 始终写到仓库根目录。
REPO_FLAG="$REPO_URL/$REPO_BRANCH"
if [[ -n "$COMMIT_HASH" && "$COMMIT_HASH" != "none" ]]; then
    REPO_FLAG="$REPO_FLAG/$COMMIT_HASH"
fi
echo "$REPO_FLAG" >"$REPO_ROOT/repo_flag"
git_retry clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"

# GitHub Action 移除国内下载源
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi
