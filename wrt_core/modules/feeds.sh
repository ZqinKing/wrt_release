#!/usr/bin/env bash

# 预设基础路径变量（如果外部未定义，则默认为当前脚本所在目录）
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
FEEDS_CONF="${FEEDS_CONF:-feeds.conf.default}"

update_feeds() {
    # 确定 feeds 配置文件路径
    local FEEDS_PATH="$BUILD_DIR/$FEEDS_CONF"
    if [[ -f "$BUILD_DIR/feeds.conf" ]]; then
        FEEDS_PATH="$BUILD_DIR/feeds.conf"
    fi

    # 清理并防止重复项
    sed -i '/^#/d' "$FEEDS_PATH"
    sed -i '/packages_ext/d' "$FEEDS_PATH"

    # 注入第三方源
    if ! grep -q "small8" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git small8 https://github.com/kenzok8/jell" >>"$FEEDS_PATH"
    fi

    if ! grep -q "openwrt-passwall" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall;main" >>"$FEEDS_PATH"
    fi

    if ! grep -q "openwrt_bandix" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo 'src-git openwrt_bandix https://github.com/timsaya/openwrt-bandix.git;main' >>"$FEEDS_PATH"
    fi

    if ! grep -q "luci_app_bandix" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo 'src-git luci_app_bandix https://github.com/timsaya/luci-app-bandix.git;main' >>"$FEEDS_PATH"
    fi

    # 兼容性补丁
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    # 使用绝对/相对路径调用 feeds 脚本
    "$BUILD_DIR/scripts/feeds" update -a
}

install_feeds() {
    # 确保 feeds 索引已更新
    "$BUILD_DIR/scripts/feeds" update -i

    # 遍历并安装
    for dir in "$BUILD_DIR"/feeds/*; do
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [[ ! "$dir" == *.index ]] && [[ ! "$dir" == *.targetindex ]]; then
            local feed_name=$(basename "$dir")
            if [[ "$feed_name" == "small8" ]]; then
                # 如果脚本中有定义这些特殊函数则调用，否则回退到标准安装
                if declare -f install_small8 > /dev/null; then install_small8; fi
                if declare -f install_fullconenat > /dev/null; then install_fullconenat; fi
                "$BUILD_DIR/scripts/feeds" install -f -ap "$feed_name"
            elif [[ "$feed_name" == "passwall" ]]; then
                if declare -f install_passwall > /dev/null; then install_passwall; fi
                "$BUILD_DIR/scripts/feeds" install -f -ap "$feed_name"
            else
                "$BUILD_DIR/scripts/feeds" install -f -ap "$feed_name"
            fi
        fi
    done
}
