#!/usr/bin/env bash
# ============================================================================
# 文件名: utils.sh
# 描述: 基础工具库，提供日志记录、错误处理和依赖检查功能
# 作者: ZqinKing
# ============================================================================

# ANSI 颜色代码定义
COLOR_RESET='\033[0m'      # 重置颜色
COLOR_RED='\033[0;31m'     # 红色 - 用于错误信息
COLOR_GREEN='\033[0;32m'   # 绿色 - 用于成功/信息
COLOR_YELLOW='\033[0;33m'  # 黄色 - 用于警告信息
COLOR_BLUE='\033[0;34m'    # 蓝色 - 保留
COLOR_CYAN='\033[0;36m'    # 青色 - 用于调试信息

# DRY_RUN 标志，默认为 0（关闭）
# 当设置为 1 时，命令只会打印而不会实际执行
DRY_RUN=${DRY_RUN:-0}

# ============================================================================
# 日志函数
# ============================================================================

# 获取当前时间戳
# 返回格式: YYYY-MM-DD HH:MM:SS
timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# 输出信息级别日志（绿色）
# 参数: $1 - 日志消息
log_info() {
    echo -e "${COLOR_GREEN}[INFO] $(timestamp) $1${COLOR_RESET}"
}

# 输出警告级别日志（黄色）
# 参数: $1 - 日志消息
# 注意: 输出到 stderr
log_warn() {
    echo -e "${COLOR_YELLOW}[WARN] $(timestamp) $1${COLOR_RESET}" >&2
}

# 输出错误级别日志（红色）
# 参数: $1 - 日志消息
# 注意: 输出到 stderr
log_error() {
    echo -e "${COLOR_RED}[ERROR] $(timestamp) $1${COLOR_RESET}" >&2
}

# 输出调试级别日志（青色）
# 参数: $1 - 日志消息
# 注意: 仅当 VERBOSE=1 时才会输出
log_debug() {
    if [[ "${VERBOSE:-0}" == "1" ]]; then
        echo -e "${COLOR_CYAN}[DEBUG] $(timestamp) $1${COLOR_RESET}"
    fi
}

# ============================================================================
# 命令执行包装器
# ============================================================================

# 执行命令的包装函数，支持错误处理和 dry-run 模式
# 用法: try_run "命令" [忽略错误标志]
# 参数:
#   $1 - 要执行的命令字符串
#   $2 - 忽略错误标志（可选）: 1=忽略错误继续执行, 0=遇错退出（默认）
# 返回: 命令的退出码
try_run() {
    local cmd="$1"
    local ignore_error="${2:-0}"
    local exit_code=0

    # Dry-run 模式：只打印命令，不实际执行
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] 将执行: $cmd"
        return 0
    fi

    log_debug "执行命令: $cmd"
    eval "$cmd"
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        if [[ "$ignore_error" == "1" ]]; then
            log_warn "命令执行失败，退出码 $exit_code（已忽略）: $cmd"
            return $exit_code
        else
            log_error "命令执行失败，退出码 $exit_code: $cmd"
            exit $exit_code
        fi
    fi
}

# ============================================================================
# 依赖检查
# ============================================================================

# 检查系统依赖工具是否已安装
# 用法: check_deps "工具1" "工具2" ...
# 参数: 需要检查的工具名称列表
# 行为: 如果有任何工具缺失，将输出错误信息并退出脚本
check_deps() {
    local deps=("$@")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必要的依赖工具: ${missing_deps[*]}"
        log_error "请先安装这些工具后再试。"
        exit 1
    fi
    
    log_info "所有依赖检查通过。"
}
