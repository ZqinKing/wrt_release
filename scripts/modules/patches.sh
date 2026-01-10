#!/usr/bin/env bash
# ============================================================================
# 文件名: patches.sh
# 描述: 补丁管理模块，用于应用远程和本地补丁文件
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"

# ============================================================================
# 远程补丁应用
# ============================================================================

# 应用远程补丁文件
# 用法: apply_remote_patches [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 从配置中指定的 URL 下载并替换目标文件
apply_remote_patches() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在应用远程补丁..."
    
    # ath11k_fw: 更新 ath11k-firmware 的 Makefile
    local ath11k_url=$(config_get_value '.patches.ath11k_fw')
    if [[ -n "$ath11k_url" && "$ath11k_url" != "null" ]]; then
        local target="$build_dir/package/firmware/ath11k-firmware/Makefile"
        if [[ -d "$(dirname "$target")" ]]; then
            log_info "正在更新 ath11k-firmware Makefile..."
            try_run "curl -fsSL -o \"$target\" \"$ath11k_url\""
        fi
    fi
    
    # tcping: 更新 tcping 的 Makefile
    local tcping_url=$(config_get_value '.patches.tcping')
    if [[ -n "$tcping_url" && "$tcping_url" != "null" ]]; then
        local target="$build_dir/feeds/small8/tcping/Makefile"
        if [[ -d "$(dirname "$target")" ]]; then
            log_info "正在更新 tcping Makefile..."
            try_run "curl -fsSL -o \"$target\" \"$tcping_url\""
        fi
    fi
    
    # istore_backend: 更新 quickstart 的后端脚本
    local istore_url=$(config_get_value '.patches.istore_backend')
    if [[ -n "$istore_url" && "$istore_url" != "null" ]]; then
        local target="$build_dir/feeds/small8/luci-app-quickstart/luasrc/controller/istore_backend.lua"
        if [[ -f "$target" ]]; then
            log_info "正在更新 istore_backend.lua..."
            try_run "curl -fsSL -o \"$target\" \"$istore_url\""
        fi
    fi
}

# ============================================================================
# 本地补丁应用
# ============================================================================

# 应用本地补丁文件
# 用法: apply_local_patches [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 根据配置将本地文件复制到构建目录的指定位置
apply_local_patches() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在应用本地补丁..."
    local patches_count=$(config_get_value '.local_patches | length')
    local base_path="$(dirname "${BASH_SOURCE[0]}")/../../"  # 项目根目录
    
    for ((i=0; i<patches_count; i++)); do
        local src=$(config_get_value ".local_patches[$i].src")
        local dest=$(config_get_value ".local_patches[$i].dest")
        local mode=$(config_get_value ".local_patches[$i].mode")
        
        # 处理源文件路径（支持绝对路径和相对路径）
        local src_path=""
        if [[ "$src" = /* ]]; then
            src_path="$src"
        else
            src_path="$base_path/$src"
        fi
        
        local dest_path="$build_dir/$dest"
        
        if [[ -f "$src_path" ]]; then
            # 确保目标目录存在
            mkdir -p "$(dirname "$dest_path")"
            
            log_info "正在安装补丁: $src -> $dest"
            if [[ -n "$mode" && "$mode" != "null" ]]; then
                try_run "install -Dm$mode \"$src_path\" \"$dest_path\""
            else
                try_run "install -D \"$src_path\" \"$dest_path\""
            fi
        else
            log_warn "本地补丁源文件不存在: $src_path"
        fi
    done
}

# ============================================================================
# 主入口函数
# ============================================================================

# 补丁应用主函数
# 用法: apply_patches [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 依次应用远程补丁和本地补丁
apply_patches() {
    local build_dir="$1"
    
    apply_remote_patches "$build_dir"
    apply_local_patches "$build_dir"
}
