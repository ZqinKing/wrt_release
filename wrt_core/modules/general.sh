#!/usr/bin/env bash
# Module: General Preparation

# --- 基础变量初始化 ---
# 确保在没有外部变量传入时也能安全运行
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
REPO_BRANCH="${REPO_BRANCH:-main}"
COMMIT_HASH="${COMMIT_HASH:-none}"

# 1. 克隆仓库逻辑
clone_repo() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Step: 克隆仓库 $REPO_URL 分支: $REPO_BRANCH"
        if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"; then
            echo "Error: 克隆仓库失败，请检查网络或 URL: $REPO_URL" >&2
            exit 1
        fi
    fi
}

# 2. 清理环境逻辑
clean_up() {
    echo "Step: 正在清理编译临时文件..."
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Warning: 目录 $BUILD_DIR 不存在，跳过清理"
        return 0
    fi
    
    # 使用 pushd 确保路径切换安全，不会因为 cd 失败而删错目录
    pushd "$BUILD_DIR" > /dev/null || return 1

    # 清理常见的残留配置和临时文件
    rm -rf .config tmp logs
    mkdir -p tmp logs

    # 执行 feeds 清理（如果脚本存在）
    if [[ -x "scripts/feeds" ]]; then
        ./scripts/feeds clean -a
    fi

    # 特殊处理：针对 IPQ60xx 等机型，清理可能导致 NSS 冲突的工具链残余
    [ -d "staging_dir" ] && find staging_dir -name ".built" -delete

    popd > /dev/null
}

# 3. 重置并拉取源码
reset_feeds_conf() {
    echo "Step: 正在更新源码并重置状态..."
    pushd "$BUILD_DIR" > /dev/null || exit 1

    # 获取远程最新状态并强制重置，防止本地改动干扰
    git fetch --all --depth 1
    echo "重置到 origin/$REPO_BRANCH"
    if ! git reset --hard "origin/$REPO_BRANCH"; then
        echo "Warning: 重置到远程分支失败，尝试重置本地分支"
        git reset --hard "$REPO_BRANCH"
    fi
    
    git clean -f -d

    # 如果指定了特定 Commit 则切换
    if [[ "$COMMIT_HASH" != "none" && -n "$COMMIT_HASH" ]]; then
        echo "切换到特定提交: $COMMIT_HASH"
        git checkout "$COMMIT_HASH"
    fi

    popd > /dev/null
}

# 4. 修复之前报错缺失的函数 (CRITICAL FIX)
remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    echo "Step: 检查并移除 target.mk 中的默认 tweak 软件包..."
    
    if [[ -f "$target_mk" ]]; then
        # 检查是否存在定义，存在则用 sed 注释掉
        if grep -q "DEFAULT_PACKAGES\.tweak" "$target_mk"; then
            # 使用 # 注释掉该行，防止编译时引入冲突的包
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
            echo "Success: 已成功注释 target.mk 中的 Tweak 软件包"
        else
            echo "Skip: target.mk 中未发现 Tweak 包定义，无需修改"
        fi
    else
        echo "Warning: 文件 $target_mk 不存在，跳过该步骤"
    fi
}
