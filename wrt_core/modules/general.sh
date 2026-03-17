#!/usr/bin/env bash
# Module: General Preparation

# --- 基础变量初始化 (建议添加) ---
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
REPO_BRANCH="${REPO_BRANCH:-main}"
COMMIT_HASH="${COMMIT_HASH:-none}"

clone_repo() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        # 增加引用保护路径，防止空格导致失败
        if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"; then
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
    
    # 始终使用绝对路径或在子 shell 中操作，防止 cd 失败后 rm 删错地方
    cd "$BUILD_DIR" || { echo "无法进入目录 $BUILD_DIR"; return 1; }

    echo "正在清理临时文件和配置..."
    
    # 使用强制删除但避免通配符报错
    [ -f ".config" ] && rm -f ".config"
    [ -d "tmp" ] && rm -rf "tmp"
    
    # 修正：rm -rf "logs/*" 可能因为找不到文件报错，直接删目录或清空内容
    if [[ -d "logs" ]]; then
        rm -rf logs
        mkdir -p logs
    fi

    if [[ -d "feeds" ]]; then
        # 确保使用当前源码内的 feeds 脚本
        ./scripts/feeds clean
    fi

    mkdir -p "tmp"
    echo "1" > "tmp/.build"
}

reset_feeds_conf() {
    # 确保在正确的目录下操作
    cd "$BUILD_DIR" || exit 1

    echo "重置仓库状态到 $REPO_BRANCH..."
    
    # 1. 强制回退并清理未跟踪文件
    git reset --hard "origin/$REPO_BRANCH"
    git clean -f -d
    
    # 2. 拉取最新代码
    if ! git pull; then
        echo "警告：git pull 失败，可能存在网络问题或本地冲突"
    fi

    # 3. 如果指定了特定的 Commit，则切换
    if [[ "$COMMIT_HASH" != "none" && -n "$COMMIT_HASH" ]]; then
        echo "切换到特定提交: $COMMIT_HASH"
        git checkout "$COMMIT_HASH"
    fi
}
