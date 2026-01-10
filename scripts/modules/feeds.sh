#!/usr/bin/env bash
# ============================================================================
# 文件名: feeds.sh
# 描述: Feeds 管理模块，负责 OpenWrt feeds.conf 的生成与管理
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"

# ============================================================================
# Feeds 配置管理
# ============================================================================

# 设置 Feeds 配置文件
# 用法: setup_feeds [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为:
#   1. 备份原有的 feeds.conf 文件
#   2. 根据配置删除不需要的 feed 源
#   3. 根据配置添加新的 feed 源
setup_feeds() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在设置 Feeds 配置 (目录: $build_dir)..."

    local feeds_conf="$build_dir/$CONF_FEEDS_CONF"
    
    # 处理 feeds.conf 存在而 feeds.conf.default 不存在的情况
    if [[ -f "$build_dir/feeds.conf" ]]; then
        feeds_conf="$build_dir/feeds.conf"
    fi

    if [[ ! -f "$feeds_conf" ]]; then
        log_error "Feeds 配置文件不存在: $feeds_conf"
        return 1
    fi

    # 备份原配置文件
    try_run "cp \"$feeds_conf\" \"$feeds_conf.bak\""

    # 删除不需要的行
    log_info "正在清理 Feeds 配置..."
    local remove_patterns=$(config_get_json '.feeds.remove_lines[]')
    
    for pattern in $remove_patterns; do
        # jq 返回的字符串带引号，需要去除
        pattern="${pattern%\"}"
        pattern="${pattern#\"}"
        
        # 使用 sed 删除匹配的行
        try_run "sed -i '/$pattern/d' \"$feeds_conf\""
    done

    # 添加新的 feed 源
    log_info "正在添加新的 Feed 源..."
    local feeds_count=$(config_get_value '.feeds.add | length')
    
    for ((i=0; i<feeds_count; i++)); do
        local name=$(config_get_value ".feeds.add[$i].name")
        local url=$(config_get_value ".feeds.add[$i].url")
        
        # 检查是否已存在同名 feed
        if ! grep -q "$name" "$feeds_conf"; then
            # 确保文件末尾有换行符
            if [[ -n "$(tail -c 1 "$feeds_conf")" ]]; then
                echo "" >> "$feeds_conf"
            fi
            echo "src-git $name $url" >> "$feeds_conf"
            log_info "已添加 Feed: $name -> $url"
        else
            log_info "Feed $name 已存在，跳过添加。"
        fi
    done

    # 修复 bpf.mk 缺失问题（来自原脚本的兼容性处理）
    if [[ ! -f "$build_dir/include/bpf.mk" ]]; then
        log_info "创建缺失的 bpf.mk 文件..."
        try_run "touch \"$build_dir/include/bpf.mk\""
    fi
}

# ============================================================================
# Feeds 更新与安装
# ============================================================================

# 更新并安装 Feeds
# 用法: update_and_install_feeds [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为:
#   1. 执行 feeds update -a 更新所有 feed 源
#   2. 根据配置安装指定 feed 中的特定软件包
#   3. 执行 feeds install -a 安装所有软件包
update_and_install_feeds() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在更新 Feeds..."
    try_run "$build_dir/scripts/feeds update -a"

    log_info "正在安装 Feeds..."
    
    # 检查是否有特定 feed 的安装规则
    # 这部分处理原脚本中 install_small8 的逻辑
    local feed_installs=$(config_get_json '.packages.install_feeds')
    
    if [[ "$feed_installs" != "null" ]]; then
        local feed_names=$(echo "$feed_installs" | jq -r 'keys[]')
        
        for feed in $feed_names; do
            local pkgs=$(echo "$feed_installs" | jq -r ".\"$feed\"[]")
            # 将软件包列表用空格连接
            pkgs=$(echo "$pkgs" | tr '\n' ' ')
            
            if [[ -n "$pkgs" ]]; then
                log_info "正在从 $feed 安装指定软件包..."
                try_run "$build_dir/scripts/feeds install -p $feed -f $pkgs"
            fi
        done
    fi

    # 安装所有其他 feeds
    # 原脚本逻辑:
    # ./scripts/feeds update -i
    # for dir in feeds/*; do install -f -ap $(basename dir); done
    
    log_info "正在安装所有其他 Feeds..."
    try_run "$build_dir/scripts/feeds install -a"
}
