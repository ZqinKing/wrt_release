#!/usr/bin/env bash
# ============================================================================
# 文件名: packages.sh
# 描述: 软件包管理模块，处理软件包的克隆、版本替换和移除
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/git.sh"

# ============================================================================
# 软件包移除
# ============================================================================

# 移除不需要的软件包
# 用法: remove_packages [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 根据配置文件中的 packages.remove 列表删除指定的软件包目录
remove_packages() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在移除不需要的软件包..."
    local remove_list=$(config_get_json '.packages.remove[]')
    
    # 软件包可能存在的目录列表
    local search_dirs=(
        "feeds/luci/applications"
        "feeds/luci/themes"
        "feeds/packages/net"
        "feeds/packages/utils"
        "feeds/small8"
        "package"
    )

    for pkg in $remove_list; do
        pkg="${pkg%\"}"
        pkg="${pkg#\"}"
        
        for dir in "${search_dirs[@]}"; do
            local target="$build_dir/$dir/$pkg"
            if [[ -d "$target" ]]; then
                log_info "正在删除: $target"
                try_run "rm -rf \"$target\""
            fi
        done
    done
    
    # 特殊处理：删除 istore 包（来自原脚本）
    if [[ -d "$build_dir/package/istore" ]]; then
         try_run "rm -rf \"$build_dir/package/istore\""
    fi
}

# ============================================================================
# Golang 版本更新
# ============================================================================

# 更新 Golang 到指定版本
# 用法: update_golang [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 删除原有的 golang 包，从配置指定的仓库克隆新版本
update_golang() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    local golang_repo=$(config_get_json '.packages.golang.repo')
    local golang_branch=$(config_get_json '.packages.golang.branch')
    
    # 去除 jq 返回的引号
    golang_repo="${golang_repo%\"}"
    golang_repo="${golang_repo#\"}"
    golang_branch="${golang_branch%\"}"
    golang_branch="${golang_branch#\"}"

    if [[ -d "$build_dir/feeds/packages/lang/golang" ]]; then
        log_info "正在更新 Golang..."
        try_run "rm -rf \"$build_dir/feeds/packages/lang/golang\""
        
        git_clone_or_update "$golang_repo" "$golang_branch" "$build_dir/feeds/packages/lang/golang"
    fi
}

# ============================================================================
# 自定义软件包安装（并行处理）
# ============================================================================

# 安装自定义软件包
# 用法: install_custom_packages [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为:
#   - 并行克隆配置中定义的自定义软件包
#   - 支持稀疏检出（sparse checkout）
#   - 执行软件包特定的后处理钩子
install_custom_packages() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi

    log_info "正在安装自定义软件包（并行模式）..."
    local custom_count=$(config_get_value '.packages.custom_add | length')
    local pids=()
    
    for ((i=0; i<custom_count; i++)); do
        (
            local name=$(config_get_value ".packages.custom_add[$i].name")
            local repo=$(config_get_value ".packages.custom_add[$i].repo")
            local path=$(config_get_value ".packages.custom_add[$i].path")
            local sparse=$(config_get_value ".packages.custom_add[$i].sparse_checkout // null")
            
            local target_path="$build_dir/$path"
            
            # 确保父目录存在
            mkdir -p "$(dirname "$target_path")"
            
            if [[ "$sparse" != "null" ]]; then
                # 处理稀疏检出
                local dirs=($(echo "$sparse" | jq -r '.[]'))
                git_sparse_checkout "$repo" "master" "$target_path" "${dirs[@]}"
            else
                 # 删除已存在的目录后重新克隆
                 if [[ -d "$target_path" ]]; then
                     log_info "正在删除已存在的目录: $target_path"
                     try_run "rm -rf \"$target_path\""
                 fi
                 
                 git_clone_or_update "$repo" "" "$target_path"
            fi
            
            # ================================================================
            # 软件包特定的后处理钩子
            # ================================================================
            
            # luci-app-athena-led: 设置可执行权限
            if [[ "$name" == "luci-app-athena-led" ]]; then
                 try_run "chmod +x \"$target_path/root/usr/sbin/athena-led\""
                 try_run "chmod +x \"$target_path/root/etc/init.d/athena_led\""
            fi
            
            # smartdns: 应用补丁和修改 Makefile
            if [[ "$name" == "smartdns" ]]; then
                 if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../../patches/100-smartdns-optimize.patch" ]]; then
                     install -Dm644 "$(dirname "${BASH_SOURCE[0]}")/../../patches/100-smartdns-optimize.patch" "$target_path/patches/100-smartdns-optimize.patch"
                 fi
                 if [[ -f "$target_path/Makefile" ]]; then
                     # 直接执行 sed，不通过 try_run/eval 以避免 Makefile 变量被 shell 解析
                     # $(TARGET_CC) 和 $(TARGET_CC_NOCACHE) 是 Makefile 变量，不是 shell 变量
                     sed -i '/define Build\/Compile\/smartdns-ui/,/endef/s/CC=$(TARGET_CC)/CC="$(TARGET_CC_NOCACHE)"/' "$target_path/Makefile" || log_warn "修改 smartdns Makefile 失败"
                 fi
            fi
            
            # luci-app-diskman: 修改 Makefile 中的依赖
            if [[ "$name" == "luci-app-diskman" ]]; then
                 if [[ -f "$target_path/Makefile" ]]; then
                    try_run "sed -i 's/fs-ntfs /fs-ntfs3 /g' \"$target_path/Makefile\""
                    try_run "sed -i '/ntfs-3g-utils /d' \"$target_path/Makefile\""
                 fi
            fi
            
            # luci-app-quickfile: 复杂的 sed 替换（暂时跳过）
            if [[ "$name" == "luci-app-quickfile" ]]; then
                 if [[ -f "$target_path/quickfile/Makefile" ]]; then
                    log_warn "跳过 quickfile 的复杂 sed 替换（TODO）"
                 fi
            fi
        ) &
        pids+=($!)
    done
    
    # 等待所有后台进程完成
    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done
    
    if [[ $failed -ne 0 ]]; then
        log_error "部分软件包安装失败。"
    fi
}

# ============================================================================
# 默认设置包检查
# ============================================================================

# 检查并安装 default-settings 包
# 用法: check_default_settings [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 如果 default-settings 包不存在，从 immortalwrt 仓库克隆
check_default_settings() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi
    
    local settings_dir="$build_dir/package/emortal/default-settings"
    if [[ -z "$(find "$build_dir/package" -type d -name "default-settings" -print -quit 2>/dev/null)" ]]; then
        log_info "default-settings 包不存在，正在从 immortalwrt 克隆..."
        local tmp_dir=$(mktemp -d)
        
        git_sparse_checkout "https://github.com/immortalwrt/immortalwrt.git" "" "$tmp_dir" "package/emortal/default-settings"
        
        mkdir -p "$(dirname "$settings_dir")"
        try_run "mv \"$tmp_dir/package/emortal/default-settings\" \"$settings_dir\""
        try_run "rm -rf \"$tmp_dir\""
    fi
}

# ============================================================================
# GeoIP 数据更新
# ============================================================================

# 更新 GeoIP 数据文件
# 用法: update_geoip [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 将 geoip.dat 替换为精简版的 geoip-only-cn-private.dat
update_geoip() {
    local build_dir="$1"
    if [[ -z "$build_dir" ]]; then build_dir="$CONF_BUILD_DIR"; fi
    
    local geodata_path="$build_dir/package/feeds/small8/v2ray-geodata/Makefile"
    if [[ -f "$geodata_path" ]]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' "$geodata_path" | grep -oE "[0-9]{1,}")
        if [[ -n "$GEOIP_VER" ]]; then
            log_info "正在更新 GeoIP 数据..."
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            
            local old_SHA256
            old_SHA256=$(curl -fsSL "$base_url/geoip.dat.sha256sum" | awk '{print $1}')
            
            local new_SHA256
            new_SHA256=$(curl -fsSL "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}')
            
            if [[ -n "$old_SHA256" && -n "$new_SHA256" ]]; then
                try_run "sed -i \"s|=geoip.dat|=geoip-only-cn-private.dat|g\" \"$geodata_path\""
                try_run "sed -i \"s/$old_SHA256/$new_SHA256/g\" \"$geodata_path\""
            else
                log_warn "获取 GeoIP 校验和失败"
            fi
        fi
    fi
}

# ============================================================================
# Lucky 软件包更新
# ============================================================================

# 更新 Lucky 软件包配置
# 用法: update_lucky [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 修改 Lucky 的默认配置和 Makefile
update_lucky() {
    local build_dir="$1"
    if [[ -z "$build_dir" ]]; then build_dir="$CONF_BUILD_DIR"; fi
    
    # 修改默认配置
    local lucky_conf="$build_dir/feeds/small8/lucky/files/luckyuci"
    if [[ -f "$lucky_conf" ]]; then
        # 直接执行 sed，不通过 try_run/eval 以避免转义问题
        sed -i "s/option enabled '1'/option enabled '0'/g" "$lucky_conf" || log_warn "修改 lucky 配置 enabled 失败"
        sed -i "s/option logger '1'/option logger '0'/g" "$lucky_conf" || log_warn "修改 lucky 配置 logger 失败"
        log_info "已更新 Lucky 默认配置"
    fi
    
    # 修改 Makefile 以使用本地补丁
    local makefile_path="$build_dir/feeds/small8/lucky/Makefile"
    local patches_dir
    patches_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/patches"
    
    if [[ -f "$makefile_path" ]]; then
        # 查找本地补丁文件
        local patch_file
        patch_file=$(find "$patches_dir" -maxdepth 1 -name "lucky_*.tar.gz" -printf "%f\n" 2>/dev/null | head -n 1)
        
        if [[ -n "$patch_file" ]]; then
            # 从文件名提取版本号
            local version
            version=$(echo "$patch_file" | sed -n 's/^lucky_\([^_]*\)_Linux.*$/\1/p')
            
            if [[ -n "$version" ]]; then
                log_info "正在更新 Lucky Makefile（使用本地补丁版本 $version）..."
                
                # 首先删除 wget 行（直接执行）
                sed -i '/wget/d' "$makefile_path" || log_warn "删除 wget 行失败"
                
                # 使用 awk 在 "define Build/Prepare" 后插入补丁安装行
                # 注意：这里的 $(TOPDIR) 等是 Makefile 变量，不是 shell 变量
                local patch_line
                patch_line=$'\t'"[ -f \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(PKG_BUILD_DIR)/\$(PKG_NAME)_\$(PKG_VERSION)_Linux_\$(LUCKY_ARCH).tar.gz"
                
                if grep -q "define Build/Prepare" "$makefile_path"; then
                    # 使用 awk 安全地插入行，避免 eval 解析问题
                    awk -v line="$patch_line" '
                        /define Build\/Prepare/ {
                            print
                            getline
                            print
                            print line
                            next
                        }
                        { print }
                    ' "$makefile_path" > "${makefile_path}.tmp" && mv "${makefile_path}.tmp" "$makefile_path"
                    
                    if [[ $? -eq 0 ]]; then
                        log_info "已更新 Lucky Makefile"
                    else
                        log_warn "更新 Lucky Makefile 失败"
                    fi
                fi
            else
                log_warn "无法从补丁文件名提取版本号: $patch_file"
            fi
        else
            log_debug "未找到 Lucky 本地补丁文件，跳过 Makefile 修改"
        fi
    fi
}

# ============================================================================
# 通用软件包版本更新
# ============================================================================

# 更新单个软件包的版本
# 用法: update_single_package "软件包名" [分支类型] [版本号]
# 参数:
#   $1 - 软件包名称
#   $2 - 分支类型（releases/tags，默认 releases）
#   $3 - 指定版本号（可选，不指定则自动获取最新版本）
# 行为: 从 GitHub API 获取最新版本并更新 Makefile
update_single_package() {
    local pkg_name="$1"
    local branch="${2:-releases}"
    local version="$3"
    
    local build_dir="$CONF_BUILD_DIR"
    local dir=$(find "$build_dir/package" \( -type d -o -type l \) -name "$pkg_name" 2>/dev/null | head -n 1)
    
    if [[ -z "$dir" ]]; then return 0; fi
    
    local mk_path="$dir/Makefile"
    if [[ -f "$mk_path" ]]; then
        log_info "正在检查 $pkg_name 的更新..."
        
        # 从 Makefile 提取仓库 URL
        local pkg_repo=$(grep -oE "^PKG_GIT_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [[ -z "$pkg_repo" ]]; then
            pkg_repo=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
        fi
        
        if [[ -z "$pkg_repo" ]]; then
            log_warn "无法提取 $pkg_name 的仓库地址"
            return 1
        fi
        
        local pkg_ver="$version"
        if [[ -z "$pkg_ver" ]]; then
            pkg_ver=$(curl -fsSL "https://api.github.com/repos/$pkg_repo/$branch" | jq -r '.[0] | .tag_name // .name')
        fi
        
        if [[ -z "$pkg_ver" || "$pkg_ver" == "null" ]]; then
            log_warn "获取 $pkg_name 版本失败"
            return 1
        fi
        
        local commit_sha
        commit_sha=$(curl -fsSL "https://api.github.com/repos/$pkg_repo/tags" | jq -r ".[] | select(.name==\"$pkg_ver\") | .commit.sha" | cut -c1-7)
        
        if [[ -n "$commit_sha" ]]; then
            try_run "sed -i 's/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:=$commit_sha/g' \"$mk_path\""
        fi
        
        # 清理版本号字符串
        local clean_ver=$(echo "$pkg_ver" | grep -oE "[\.0-9]{1,}")
        
        try_run "sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=$clean_ver/g' \"$mk_path\""
        log_info "已更新 $pkg_name 到版本 $clean_ver"
    fi
}

# 更新特定软件包到指定版本
# 用法: update_specific_packages
# 行为: 更新 runc, containerd, docker, dockerd 到指定版本
update_specific_packages() {
    update_single_package "runc" "releases" "v1.2.6"
    update_single_package "containerd" "releases" "v1.7.27"
    update_single_package "docker" "tags" "v28.2"
    update_single_package "dockerd" "releases" "v28.2.2"
}

# ============================================================================
# 主入口函数
# ============================================================================

# 软件包管理主函数
# 用法: manage_packages [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 按顺序执行所有软件包管理操作
manage_packages() {
    local build_dir="$1"
    
    remove_packages "$build_dir"
    update_golang "$build_dir"
    install_custom_packages "$build_dir"
    check_default_settings "$build_dir"
    
    update_geoip "$build_dir"
    update_lucky "$build_dir"
    update_specific_packages
}
