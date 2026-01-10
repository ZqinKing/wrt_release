#!/usr/bin/env bash
# ============================================================================
# 文件名: config.sh
# 描述: 配置解析库，支持 JSON 和 INI 配置文件的读取和环境变量覆盖
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================================
# 全局配置变量
# 这些变量在 load_config 函数执行后会被填充
# ============================================================================
export CONF_REPO_URL=""        # 主仓库 URL
export CONF_REPO_BRANCH=""     # 主仓库分支
export CONF_BUILD_DIR=""       # 构建目录路径
export CONF_COMMIT_HASH=""     # 指定的 Commit Hash（可选）
export CONF_LAN_ADDR=""        # 默认 LAN IP 地址
export CONF_THEME_SET=""       # 默认主题名称
export CONF_FEEDS_CONF=""      # Feeds 配置文件名
export CURRENT_CONFIG_FILE=""  # 当前加载的配置文件路径
export CONF_DEVICE=""          # 设备型号
export CONF_DEVICE_CONFIG=""   # 设备配置文件路径
export CONF_NSS_CONFIG=""      # NSS 配置文件路径
export CONF_PROXY_CONFIG=""    # 代理配置文件路径

# ============================================================================
# INI 文件解析函数
# ============================================================================

# 从 INI 文件读取指定键的值
# 用法: read_ini_by_key "INI文件路径" "键名"
# 参数:
#   $1 - INI 文件路径
#   $2 - 要读取的键名
# 返回: 键对应的值
read_ini_by_key() {
    local ini_file="$1"
    local key="$2"
    
    if [[ ! -f "$ini_file" ]]; then
        log_error "INI 文件不存在: $ini_file"
        return 1
    fi
    
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$ini_file"
}

# 加载 INI 配置文件
# 用法: load_ini_config "INI文件路径"
# 参数:
#   $1 - INI 文件路径
# 行为: 读取 INI 文件中的配置并设置到全局变量
load_ini_config() {
    local ini_file="$1"
    
    if [[ ! -f "$ini_file" ]]; then
        log_error "INI 配置文件不存在: $ini_file"
        return 1
    fi
    
    log_info "正在加载 INI 配置文件: $ini_file"
    
    # 读取仓库配置
    local repo_url=$(read_ini_by_key "$ini_file" "REPO_URL")
    local repo_branch=$(read_ini_by_key "$ini_file" "REPO_BRANCH")
    local build_dir=$(read_ini_by_key "$ini_file" "BUILD_DIR")
    local commit_hash=$(read_ini_by_key "$ini_file" "COMMIT_HASH")
    
    # 如果 INI 文件中有值，则覆盖现有配置
    if [[ -n "$repo_url" ]]; then
        CONF_REPO_URL="$repo_url"
    fi
    if [[ -n "$repo_branch" ]]; then
        CONF_REPO_BRANCH="$repo_branch"
    else
        CONF_REPO_BRANCH="${CONF_REPO_BRANCH:-main}"
    fi
    if [[ -n "$build_dir" ]]; then
        CONF_BUILD_DIR="$build_dir"
    fi
    if [[ -n "$commit_hash" ]]; then
        CONF_COMMIT_HASH="$commit_hash"
    else
        CONF_COMMIT_HASH="${CONF_COMMIT_HASH:-none}"
    fi
    
    log_debug "INI 配置加载完成:"
    log_debug "  仓库地址: $CONF_REPO_URL"
    log_debug "  仓库分支: $CONF_REPO_BRANCH"
    log_debug "  构建目录: $CONF_BUILD_DIR"
    log_debug "  Commit Hash: $CONF_COMMIT_HASH"
}

# ============================================================================
# 配置加载函数
# ============================================================================

# 从 JSON 文件加载配置
# 用法: load_config [配置文件路径]
# 参数:
#   $1 - 配置文件路径（可选，默认为 config/default.json）
# 行为:
#   1. 读取 JSON 配置文件
#   2. 将配置值填充到全局变量
#   3. 支持环境变量覆盖（环境变量优先级更高）
load_config() {
    local config_file="${1:-$(dirname "${BASH_SOURCE[0]}")/../config/default.json}"
    
    # 保存配置文件路径供后续使用
    CURRENT_CONFIG_FILE="$config_file"

    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在: $config_file"
        exit 1
    fi

    # 检查 jq 是否安装
    check_deps "jq"

    log_info "正在加载配置文件: $config_file"

    # 加载仓库配置
    CONF_REPO_URL=$(jq -r '.repo.url // ""' "$config_file")
    CONF_REPO_BRANCH=$(jq -r '.repo.branch // ""' "$config_file")
    CONF_BUILD_DIR=$(jq -r '.repo.build_dir // "openwrt"' "$config_file")
    CONF_COMMIT_HASH=$(jq -r '.repo.commit_hash // "none"' "$config_file")

    # 环境变量覆盖（环境变量优先级更高）
    CONF_REPO_URL=${REPO_URL:-$CONF_REPO_URL}
    CONF_REPO_BRANCH=${REPO_BRANCH:-$CONF_REPO_BRANCH}
    CONF_BUILD_DIR=${BUILD_DIR:-$CONF_BUILD_DIR}
    CONF_COMMIT_HASH=${COMMIT_HASH:-$CONF_COMMIT_HASH}

    # 加载其他配置
    CONF_LAN_ADDR=$(jq -r '.network.lan_addr // "192.168.1.1"' "$config_file")
    CONF_THEME_SET=$(jq -r '.theme.set // "argon"' "$config_file")
    CONF_FEEDS_CONF=$(jq -r '.feeds.conf_file // "feeds.conf.default"' "$config_file")

    # 其他配置的环境变量覆盖
    CONF_LAN_ADDR=${LAN_ADDR:-$CONF_LAN_ADDR}
    CONF_THEME_SET=${THEME_SET:-$CONF_THEME_SET}

    # 调试输出
    log_debug "配置加载完成:"
    log_debug "  仓库地址: $CONF_REPO_URL"
    log_debug "  仓库分支: $CONF_REPO_BRANCH"
    log_debug "  构建目录: $CONF_BUILD_DIR"
    log_debug "  Commit Hash: $CONF_COMMIT_HASH"
    log_debug "  LAN 地址: $CONF_LAN_ADDR"
    log_debug "  主题设置: $CONF_THEME_SET"
}

# ============================================================================
# 配置读取辅助函数
# ============================================================================

# 获取 JSON 配置的子对象（返回 JSON 格式）
# 用法: config_get_json "键路径" [配置文件]
# 参数:
#   $1 - jq 格式的键路径，如 ".feeds.add"
#   $2 - 配置文件路径（可选，默认使用当前加载的配置文件）
# 返回: JSON 格式的配置值
config_get_json() {
    local key="$1"
    local config_file="$2"
    
    if [[ -z "$config_file" ]]; then
        if [[ -n "$CURRENT_CONFIG_FILE" ]]; then
            config_file="$CURRENT_CONFIG_FILE"
        else
            config_file="$(dirname "${BASH_SOURCE[0]}")/../config/default.json"
        fi
    fi
    
    jq -c "$key" "$config_file"
}

# 获取配置的原始值（返回字符串）
# 用法: config_get_value "键路径" [配置文件]
# 参数:
#   $1 - jq 格式的键路径，如 ".repo.url"
#   $2 - 配置文件路径（可选，默认使用当前加载的配置文件）
# 返回: 配置值的字符串形式
config_get_value() {
    local key="$1"
    local config_file="$2"
    
    if [[ -z "$config_file" ]]; then
        if [[ -n "$CURRENT_CONFIG_FILE" ]]; then
            config_file="$CURRENT_CONFIG_FILE"
        else
            config_file="$(dirname "${BASH_SOURCE[0]}")/../config/default.json"
        fi
    fi
    
    jq -r "$key" "$config_file"
}
