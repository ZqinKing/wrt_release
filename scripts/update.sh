#!/usr/bin/env bash
# ============================================================================
# 文件名: update.sh
# 描述: OpenWrt/ImmortalWrt 固件构建环境准备脚本 - 主入口
# 作者: ZqinKing
# 版本: 2.1.0 (重构版 - 支持设备型号)
# ============================================================================
#
# 用法:
#   ./update.sh [选项]
#   ./update.sh -D <设备型号>           # 使用设备型号配置
#
# 选项:
#   -D, --device <型号>   指定设备型号（从 deconfig/ 和 compilecfg/ 加载配置）
#   -c, --config <文件>   指定 JSON 配置文件路径（默认: config/default.json）
#   -d, --dry-run         预览模式，只打印命令不实际执行
#   -v, --verbose         详细输出模式
#   -h, --help            显示帮助信息
#
# 示例:
#   ./update.sh                                    # 使用默认配置运行
#   ./update.sh -D jdcloud_ipq60xx_immwrt          # 使用设备型号配置
#   ./update.sh -c myconfig.json                   # 使用自定义 JSON 配置
#   ./update.sh -D redmi_ax6_immwrt --dry-run      # 预览设备配置操作
#   ./update.sh -v                                 # 详细输出模式
#
# ============================================================================

set -e
set -o errexit
set -o errtrace

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置trap捕获ERR信号
trap 'error_handler' ERR

# 获取脚本所在目录和项目根目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)

# 加载库文件
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/git.sh"

# 加载功能模块
source "$SCRIPT_DIR/modules/feeds.sh"
source "$SCRIPT_DIR/modules/packages.sh"
source "$SCRIPT_DIR/modules/patches.sh"
source "$SCRIPT_DIR/modules/config_tweaks.sh"

# ============================================================================
# 默认配置
# ============================================================================
CONFIG_FILE="$SCRIPT_DIR/config/default.json"
DEVICE=""
VERBOSE=0
DRY_RUN=0

# ============================================================================
# 帮助信息
# ============================================================================

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "OpenWrt/ImmortalWrt 固件构建环境准备脚本"
    echo ""
    echo "选项:"
    echo "  -D, --device <型号>   指定设备型号（从 deconfig/ 和 compilecfg/ 加载配置）"
    echo "  -c, --config <文件>   指定 JSON 配置文件路径（默认: config/default.json）"
    echo "  -d, --dry-run         预览模式，只打印命令不实际执行"
    echo "  -v, --verbose         详细输出模式"
    echo "  -h, --help            显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                                    # 使用默认配置运行"
    echo "  $0 -D jdcloud_ipq60xx_immwrt          # 使用设备型号配置"
    echo "  $0 -c myconfig.json                   # 使用自定义 JSON 配置"
    echo "  $0 -D redmi_ax6_immwrt --dry-run      # 预览设备配置操作"
    echo ""
    echo "可用的设备型号（deconfig/ 目录下的 .config 文件）:"
    if [[ -d "$BASE_PATH/deconfig" ]]; then
        ls -1 "$BASE_PATH/deconfig"/*.config 2>/dev/null | xargs -n1 basename | sed 's/\.config$//' | sed 's/^/  /' || echo "  (无可用设备配置)"
    fi
    echo ""
}

# ============================================================================
# 参数解析
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -D|--device)
            DEVICE="$2"
            shift
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 导出全局标志供其他模块使用
export VERBOSE
export DRY_RUN

# ============================================================================
# 清理函数
# ============================================================================

# 清理构建目录
# 用法: cleanup [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为: 删除临时文件、清理 feeds 缓存
cleanup() {
    local build_dir="$1"
    
    if [[ -d "$build_dir" ]]; then
        log_info "正在清理构建目录..."
        try_run "rm -f \"$build_dir/.config\""
        try_run "rm -rf \"$build_dir/tmp\""
        try_run "rm -rf \"$build_dir/logs/*\""
        if [[ -f "$build_dir/scripts/feeds" ]]; then
            try_run "$build_dir/scripts/feeds clean"
        fi
        try_run "mkdir -p \"$build_dir/tmp\""
        try_run "echo '1' > \"$build_dir/tmp/.build\""
    fi
}

# ============================================================================
# 设备配置加载
# ============================================================================

# 加载设备配置
# 用法: load_device_config "设备型号"
# 参数:
#   $1 - 设备型号名称
# 行为:
#   1. 检查 deconfig/$device.config 和 compilecfg/$device.ini 是否存在
#   2. 从 INI 文件加载仓库配置覆盖 JSON 默认值
#   3. 设置 CONF_DEVICE_CONFIG 变量
load_device_config() {
    local device="$1"
    
    if [[ -z "$device" ]]; then
        return 0
    fi
    
    log_info "正在加载设备配置: $device"
    
    # 检查设备配置文件
    local device_config="$BASE_PATH/deconfig/${device}.config"
    local device_ini="$BASE_PATH/compilecfg/${device}.ini"
    
    if [[ ! -f "$device_config" ]]; then
        log_error "设备配置文件不存在: $device_config"
        exit 1
    fi
    
    if [[ ! -f "$device_ini" ]]; then
        log_error "设备 INI 文件不存在: $device_ini"
        exit 1
    fi
    
    # 保存设备信息到全局变量
    CONF_DEVICE="$device"
    CONF_DEVICE_CONFIG="$device_config"
    
    # 从 INI 文件加载仓库配置（覆盖 JSON 默认值）
    load_ini_config "$device_ini"
    
    # 检查是否存在 action_build 目录（GitHub Actions 环境）
    if [[ -d "$BASE_PATH/action_build" ]]; then
        CONF_BUILD_DIR="action_build"
        log_info "检测到 GitHub Actions 环境，使用构建目录: action_build"
    fi
    
    # 设置 NSS 和代理配置文件路径
    CONF_NSS_CONFIG="$BASE_PATH/deconfig/nss.config"
    CONF_PROXY_CONFIG="$BASE_PATH/deconfig/proxy.config"
    
    log_info "设备配置加载完成:"
    log_info "  设备型号: $CONF_DEVICE"
    log_info "  设备配置: $CONF_DEVICE_CONFIG"
    log_info "  仓库地址: $CONF_REPO_URL"
    log_info "  仓库分支: $CONF_REPO_BRANCH"
    log_info "  构建目录: $CONF_BUILD_DIR"
    
    export CONF_DEVICE
    export CONF_DEVICE_CONFIG
    export CONF_NSS_CONFIG
    export CONF_PROXY_CONFIG
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    log_info "=========================================="
    log_info "OpenWrt 构建环境准备脚本 v2.1.0"
    log_info "=========================================="
    
    # 阶段 1: 检查依赖
    log_info "[阶段 1/8] 检查系统依赖..."
    check_deps "jq" "curl" "git" "sed"
    
    # 阶段 2: 加载 JSON 配置
    log_info "[阶段 2/8] 加载 JSON 配置文件..."
    load_config "$CONFIG_FILE"
    
    # 阶段 2.5: 加载设备配置（如果指定了设备型号）
    if [[ -n "$DEVICE" ]]; then
        log_info "[阶段 2.5/8] 加载设备配置..."
        load_device_config "$DEVICE"
    fi
    
    local build_dir="$CONF_BUILD_DIR"
    
    # 阶段 3: 准备主仓库
    log_info "[阶段 3/8] 准备主仓库..."
    if [[ -n "$CONF_REPO_URL" ]]; then
        # 无论目录是否存在，都调用 git_clone_or_update 来确保仓库同步
        if [[ ! -d "$build_dir" ]]; then
            log_info "正在克隆主仓库..."
        else
            log_info "正在更新主仓库: $build_dir"
        fi
        
        git_clone_or_update "$CONF_REPO_URL" "$CONF_REPO_BRANCH" "$build_dir"
        
        if [[ "$CONF_COMMIT_HASH" != "none" ]]; then
            git_checkout_hash "$build_dir" "$CONF_COMMIT_HASH"
        fi
    elif [[ ! -d "$build_dir" ]]; then
        # REPO_URL 未配置且目录不存在，报错退出
        log_error "构建目录 '$build_dir' 不存在，且未配置 REPO_URL。"
        exit 1
    else
        # REPO_URL 未配置但目录存在，尝试更新现有仓库
        log_info "使用已存在的构建目录: $build_dir"
        if [[ -d "$build_dir/.git" ]]; then
            log_info "检测到 Git 仓库，尝试更新..."
            local current_branch
            current_branch=$(git -C "$build_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            try_run "git -C \"$build_dir\" reset --hard HEAD"
            try_run "git -C \"$build_dir\" clean -f -d"
            try_run "git -C \"$build_dir\" pull" || log_warn "仓库更新失败，继续使用现有版本"
        fi
    fi
    
    # 清理构建目录
    cleanup "$build_dir"
    
    # 阶段 4: 配置 Feeds
    log_info "[阶段 4/8] 配置 Feeds..."
    setup_feeds "$build_dir"
    
    # 阶段 5: 更新 Feeds
    log_info "[阶段 5/8] 更新 Feeds..."
    try_run "$build_dir/scripts/feeds update -a"
    
    # 阶段 6: 管理软件包
    log_info "[阶段 6/8] 管理软件包..."
    manage_packages "$build_dir"
    
    # 安装 Feeds
    log_info "正在安装 Feeds..."
    try_run "$build_dir/scripts/feeds install -a"
    
    # 阶段 7: 应用补丁和配置修改
    log_info "[阶段 7/8] 应用补丁和配置修改..."
    apply_patches "$build_dir"
    apply_config_tweaks "$build_dir"
    
    # 阶段 8: 应用设备配置（如果指定了设备型号）
    if [[ -n "$DEVICE" ]]; then
        log_info "[阶段 8/8] 应用设备配置..."
        apply_device_config "$build_dir"
        remove_uhttpd_dependency "$build_dir"
        
        # 执行 make defconfig 生成最终配置
        log_info "正在执行 make defconfig..."
        try_run "cd \"$build_dir\" && make defconfig"
    fi
    
    # 完成
    log_info "=========================================="
    log_info "构建环境准备完成！"
    log_info "=========================================="
    log_info ""
    log_info "后续步骤:"
    log_info "  1. cd $build_dir"
    log_info "  2. make menuconfig  # 配置编译选项"
    log_info "  3. make -j\$(nproc)  # 开始编译"
    log_info ""
}

# 执行主函数
main "$@"
