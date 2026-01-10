#!/usr/bin/env bash
# ============================================================================
# 文件名: git.sh
# 描述: Git 操作库，封装克隆、更新、重置等操作，并集成网络重试机制
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================================
# 重试配置
# ============================================================================
GIT_RETRIES=3          # 最大重试次数
GIT_RETRY_DELAY=2      # 初始重试延迟（秒）

# ============================================================================
# 重试机制
# ============================================================================

# 带重试机制的命令执行器
# 用法: retry_command "命令"
# 参数:
#   $1 - 要执行的命令字符串
# 行为:
#   - 执行命令，失败时进行线性退避重试
#   - 重试间隔: 2s, 4s, 6s...
# 返回: 命令的退出码
retry_command() {
    local cmd="$1"
    local retries=$GIT_RETRIES
    local count=0
    local exit_code=0

    until [[ $count -ge $retries ]]; do
        # 使用 try_run 执行命令，忽略错误（由本函数处理重试）
        try_run "$cmd" 1
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        count=$((count + 1))
        if [[ $count -lt $retries ]]; then
            local delay=$((GIT_RETRY_DELAY * count))  # 线性退避
            log_warn "命令执行失败（第 $count/$retries 次尝试），${delay}秒后重试..."
            sleep $delay
        fi
    done

    log_error "命令在 $retries 次尝试后仍然失败: $cmd"
    return $exit_code
}

# ============================================================================
# Git 核心操作
# ============================================================================

# 克隆或更新 Git 仓库
# 用法: git_clone_or_update "仓库URL" "分支" "目标路径" [克隆深度]
# 参数:
#   $1 - 仓库 URL
#   $2 - 分支名称（可为空）
#   $3 - 本地目标路径
#   $4 - 克隆深度（可选，默认为 1，即浅克隆）
# 行为:
#   - 如果目标目录已存在且是 Git 仓库，则执行更新
#   - 如果目标目录存在但不是 Git 仓库，则删除后重新克隆
#   - 如果目标目录不存在，则执行克隆
git_clone_or_update() {
    local url="$1"
    local branch="$2"
    local path="$3"
    local depth="${4:-1}"  # 默认浅克隆深度为 1
    
    if [[ -z "$url" || -z "$path" ]]; then
        log_error "git_clone_or_update: 缺少必要参数（URL 或路径）"
        return 1
    fi

    check_deps "git"

    if [[ -d "$path/.git" ]]; then
        # 目录存在且是 Git 仓库，执行更新
        log_info "正在更新 Git 仓库: $path"
        
        if [[ -n "$branch" ]]; then
            # 获取指定分支的最新代码并重置
            retry_command "git -C \"$path\" fetch origin \"$branch\" --depth $depth" || return 1
            retry_command "git -C \"$path\" reset --hard FETCH_HEAD" || return 1
            retry_command "git -C \"$path\" clean -fd" || return 1
        else
            retry_command "git -C \"$path\" pull" || return 1
        fi
    elif [[ -d "$path" ]]; then
        # 目录存在但不是 Git 仓库，删除后重新克隆
        log_warn "目录 $path 存在但不是 Git 仓库，将删除后重新克隆。"
        try_run "rm -rf \"$path\""
        
        log_info "正在克隆仓库 $url 到 $path..."
        local branch_arg=""
        if [[ -n "$branch" ]]; then
            branch_arg="-b \"$branch\""
        fi
        
        retry_command "git clone --depth $depth $branch_arg \"$url\" \"$path\"" || return 1
    else
        # 目录不存在，执行克隆
        log_info "正在克隆仓库 $url 到 $path..."
        local branch_arg=""
        if [[ -n "$branch" ]]; then
            branch_arg="-b \"$branch\""
        fi
        
        # 确保父目录存在
        mkdir -p "$(dirname "$path")"
        
        retry_command "git clone --depth $depth $branch_arg \"$url\" \"$path\"" || return 1
    fi
    
    return 0
}

# 检出指定的 Commit Hash
# 用法: git_checkout_hash "仓库路径" "commit_hash"
# 参数:
#   $1 - 本地仓库路径
#   $2 - 要检出的 Commit Hash
# 注意: 如果是浅克隆，可能需要先获取更多历史记录
git_checkout_hash() {
    local path="$1"
    local hash="$2"

    if [[ -z "$path" || -z "$hash" || "$hash" == "none" ]]; then
        return 0
    fi

    log_info "正在检出 Commit $hash (路径: $path)..."
    
    if ! git -C "$path" checkout "$hash"; then
        log_warn "检出失败（可能是浅克隆导致），正在获取更多历史记录..."
        # 尝试获取更多历史记录后再检出
        retry_command "git -C \"$path\" fetch --depth 100 origin" 
        
        if ! retry_command "git -C \"$path\" checkout \"$hash\""; then
            log_error "无法检出 Commit: $hash"
            return 1
        fi
    fi
}

# ============================================================================
# 稀疏检出（Sparse Checkout）
# ============================================================================

# 执行稀疏检出，只克隆仓库中的指定目录
# 用法: git_sparse_checkout "仓库URL" "分支" "目标路径" "目录1" "目录2" ...
# 参数:
#   $1 - 仓库 URL
#   $2 - 分支名称
#   $3 - 本地目标路径
#   $4+ - 要检出的目录列表
# 适用场景: 只需要大型仓库中的部分目录时，可显著减少下载量
git_sparse_checkout() {
    local url="$1"
    local branch="$2"
    local path="$3"
    shift 3
    local dirs=("$@")

    # 如果目标目录已存在，先删除
    if [[ -d "$path" ]]; then
        rm -rf "$path"
    fi
    
    mkdir -p "$path"
    
    log_info "正在执行稀疏检出: $url -> $path"
    
    # 初始化空仓库
    retry_command "git -C \"$path\" init" || return 1
    retry_command "git -C \"$path\" remote add origin \"$url\"" || return 1
    
    # 配置稀疏检出
    retry_command "git -C \"$path\" config core.sparseCheckout true" || return 1
    
    # 设置要检出的目录
    printf "%s\n" "${dirs[@]}" > "$path/.git/info/sparse-checkout"
    
    # 拉取代码
    local branch_arg="master"
    if [[ -n "$branch" ]]; then
        branch_arg="$branch"
    fi
    
    retry_command "git -C \"$path\" pull --depth 1 origin \"$branch_arg\"" || return 1
}
