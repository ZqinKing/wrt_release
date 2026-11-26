#!/usr/bin/env bash
# 上游源码拉取、清理和复位。

clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if ! git_retry clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}


clean_up() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Build directory $BUILD_DIR does not exist"
        return
    fi
    cd "$BUILD_DIR"
    if [[ -f ".config" ]]; then
        \rm -f ".config"
    fi
    if [[ -d "tmp" ]]; then
        \rm -rf "tmp"
    fi
    if [[ -d "logs" ]]; then
        \rm -rf "logs/*"
    fi
    if [[ -d "feeds" ]]; then
        ./scripts/feeds clean
    fi
    mkdir -p "tmp"
    echo "1" >"tmp/.build"
}

validate_build_repo() {
    local build_root
    local repo_root
    local source_url
    local expected_url
    local orchestrator_root
    build_root=$(cd "$BUILD_DIR" && pwd -P) || return 1
    repo_root=$(git -C "$build_root" rev-parse --show-toplevel) || return 1
    repo_root=$(cd "$repo_root" && pwd -P) || return 1
    orchestrator_root=$(cd "$BASE_PATH/.." && pwd -P) || return 1
    if [[ "$repo_root" != "$build_root" ||
          "$orchestrator_root/" == "$build_root/"* ]]; then
        echo "错误：构建目录不是独立的源码仓库：$BUILD_DIR" >&2
        return 1
    fi
    source_url=$(git -C "$build_root" remote get-url origin) || return 1
    expected_url="${REPO_URL%/}"
    expected_url="${expected_url%.git}"
    source_url="${source_url%/}"
    source_url="${source_url%.git}"
    if [[ "$source_url" != "$expected_url" ]]; then
        echo "错误：构建仓库来源不匹配：实际 $source_url，预期 $expected_url" >&2
        return 1
    fi
}


reset_feeds_conf() {
    # 所有源码修正都基于远端分支或指定提交的干净状态。
    git_retry -C "$BUILD_DIR" reset --hard "origin/$REPO_BRANCH"
    git_retry -C "$BUILD_DIR" clean -f -d
    git_retry -C "$BUILD_DIR" pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git_retry -C "$BUILD_DIR" checkout "$COMMIT_HASH"
    fi
}
