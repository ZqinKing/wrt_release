#!/usr/bin/env bash
#
# ImageBuilder Quick Build Script
# Uses an existing ImageBuilder archive and the repo's deconfig files to
# generate a firmware artifact set without a full source build.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

error_handler() {
    log_error "Error at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
    exit 1
}
trap 'error_handler' ERR

parse_packages_from_config() {
    local config_file=$1
    local packages=""
    local count_install=0
    local count_remove=0
    local count_skipped=0

    if [ ! -f "$config_file" ]; then
        log_warn "配置文件不存在: $config_file" >&2
        return 1
    fi

    log_info "从配置文件读取包列表: $(basename "$config_file")" >&2

    while IFS= read -r line; do
        local pkg=""
        local state=""

        if [[ "$line" =~ ^#\ CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)\ is\ not\ set$ ]]; then
            pkg="${BASH_REMATCH[1]}"
            state="n"
        elif [[ "$line" =~ ^CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)[[:space:]]*=[[:space:]]*([ymn]).*$ ]]; then
            pkg="${BASH_REMATCH[1]}"
            state="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # ImageBuilder only understands actual package names, not menuconfig feature toggles.
        if [[ "$pkg" =~ [A-Z] ]]; then
            ((count_skipped++))
            continue
        fi

        pkg=$(echo "$pkg" | tr -d ' ')
        pkg="${pkg//_/-}"

        if [ -z "$pkg" ]; then
            ((count_skipped++))
            continue
        fi

        if [[ "$state" == "n" ]]; then
            packages="$packages -$pkg"
            ((count_remove++))
        else
            packages="$packages $pkg"
            ((count_install++))
        fi
    done < "$config_file"

    log_info "解析完成: 安装 $count_install 个包, 移除 $count_remove 个包, 跳过 $count_skipped 个" >&2

    echo "$packages"
}

parse_profile_from_config() {
    local config_file=$1
    local line=""

    while IFS= read -r line; do
        [[ "$line" == CONFIG_TARGET_PER_DEVICE_* ]] && continue

        if [[ "$line" =~ ^CONFIG_TARGET_.*_DEVICE_([^=]+)=y$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    done < "$config_file"

    return 0
}

validate_package_list() {
    local package_list=$1
    local pkg=""

    if [[ "$package_list" == *$'\033'* || "$package_list" == *"[INFO]"* ]]; then
        log_error "包列表包含日志或 ANSI 控制字符，拒绝继续构建"
        log_error "请检查是否有命令替换捕获了日志输出"
        return 1
    fi

    for pkg in $package_list; do
        if [[ ! "$pkg" =~ ^-?[A-Za-z0-9.+_-]+$ ]]; then
            log_error "包列表包含非法 token: $(printf '%q' "$pkg")"
            return 1
        fi
    done
}

MODEL=$1
IMAGEBUILDER_URL=$2

BASE_PATH=$(cd "$(dirname "$0")" && pwd)
CORE_PATH="$BASE_PATH/wrt_core"
WORK_DIR="$BASE_PATH/imagebuilder_work"
FIRMWARE_DIR="$BASE_PATH/firmware"

if [ -z "$MODEL" ] || [ -z "$IMAGEBUILDER_URL" ]; then
    log_error "用法: $0 <model> <imagebuilder_url>"
    log_error "提示: 使用环境变量 EXTRA_PACKAGES 和 REMOVE_PACKAGES 指定额外的包"
    exit 1
fi

log_info "=========================================="
log_info "ImageBuilder 快速构建"
log_info "=========================================="
log_info "设备型号: $MODEL"
log_info "ImageBuilder URL: $IMAGEBUILDER_URL"

if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "额外安装的包: $EXTRA_PACKAGES"
fi
if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
fi

mkdir -p "$WORK_DIR"
rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
cd "$WORK_DIR"

log_info "下载 ImageBuilder..."
filename=$(basename "$IMAGEBUILDER_URL")

if [ -f "$filename" ]; then
    log_warn "文件已存在，跳过下载"
else
    wget -q --show-progress "$IMAGEBUILDER_URL" -O "$filename" || {
        log_error "下载失败"
        exit 1
    }
fi

log_info "解压 ImageBuilder..."
tar -xf "$filename"

builder_dir=$(find . -maxdepth 1 -type d -name "*imagebuilder*" | head -n 1)
if [ -z "$builder_dir" ]; then
    log_error "未找到 ImageBuilder 目录"
    exit 1
fi

cd "$builder_dir"
log_info "进入目录: $(pwd)"

CONFIG_FILE="$CORE_PATH/deconfig/${MODEL}.config"
PROFILE=""

log_info "确定设备 Profile..."

if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "未找到设备配置文件: $CONFIG_FILE"
    make info 2>/dev/null || true
    log_error "请添加 wrt_core/deconfig/${MODEL}.config，并在其中声明 CONFIG_TARGET_*_DEVICE_<profile>=y"
    exit 1
fi

PROFILE=$(parse_profile_from_config "$CONFIG_FILE")
if [ -z "$PROFILE" ]; then
    make info 2>/dev/null || true
    log_error "未能从配置文件识别 Profile: $CONFIG_FILE"
    log_info "以下是支持的设备: "
    make info
    exit 1
fi

log_info "从配置文件识别 Profile: $PROFILE"

log_info "使用 Profile: $PROFILE"
log_info "准备包列表..."

PACKAGES=$(parse_packages_from_config "$CONFIG_FILE")

if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "添加额外的包: $EXTRA_PACKAGES"
    PACKAGES="$PACKAGES $EXTRA_PACKAGES"
fi

if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
    for pkg in $REMOVE_PACKAGES; do
        PACKAGES="$PACKAGES -$pkg"
    done
fi

PACKAGES=$(echo "$PACKAGES" | xargs)
if ! validate_package_list "$PACKAGES"; then
    exit 1
fi
log_info "最终包列表: $PACKAGES"

FILES_DIR="$BASE_PATH/files"
if [ -d "$FILES_DIR" ]; then
    log_info "使用自定义文件: $FILES_DIR"
    FILES_OPT="FILES=$FILES_DIR"
else
    FILES_OPT=""
fi

log_info "开始构建固件..."
log_info "=========================================="

if ! make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    $FILES_OPT; then
    log_error "构建失败"
    exit 1
fi

log_info "=========================================="
log_info "构建成功！"
log_info "收集固件文件..."

bin_dir=$(find . -type d -name "bin" | head -n 1)
if [ -z "$bin_dir" ]; then
    log_error "未找到固件输出目录"
    exit 1
fi

find "$bin_dir" -type f \
    \( -name "*.bin" -o -name "*.img" -o -name "*.img.gz" \
    -o -name "*.manifest" -o -name "sha256sums" \) \
    -exec cp -v {} "$FIRMWARE_DIR/" \;

if [ -f "$bin_dir/targets/"*"/"*"/*.manifest" ]; then
    cp "$bin_dir/targets/"*"/"*"/*.manifest" "$FIRMWARE_DIR/packages.txt"
fi

log_info "=========================================="
log_info "固件文件已保存到: $FIRMWARE_DIR"
log_info "=========================================="

ls -lh "$FIRMWARE_DIR"
