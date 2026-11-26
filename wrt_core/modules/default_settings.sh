#!/usr/bin/env bash
# 系统默认设置与初始 distfeeds。

fix_default_set() {
    # 替换默认主题依赖，并注入系统设置和目标平台通用补丁。
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/files/uci-defaults/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    local wifi_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"
    if is_vikingyfy_owrt_build; then
        local wifi_detect_path="$BUILD_DIR/package/network/config/wifi-scripts/files/etc/hotplug.d/ieee80211/10-wifi-detect"
        local wifi_apply_line="    /usr/libexec/992_set-wifi-uci.sh --hotplug"
        local wifi_config_count
        local wifi_retry_count

        if [[ ! -f "$wifi_detect_path" ]]; then
            echo "错误：VIKINGYFY owrt 缺少预期的 IEEE 802.11 热插拔脚本：$wifi_detect_path" >&2
            return 1
        fi

        wifi_config_count=$(grep -Ec '^[[:space:]]*/sbin/wifi config$' "$wifi_detect_path" || true)
        wifi_retry_count=$(grep -Ec '^[[:space:]]*ubus call network\.wireless retry$' "$wifi_detect_path" || true)
        if [[ "$wifi_config_count" != "1" || "$wifi_retry_count" != "1" ]]; then
            echo "错误：VIKINGYFY owrt 的 IEEE 802.11 热插拔流程与预期不符，拒绝安装早期 Wi-Fi 默认值。" >&2
            return 1
        fi

        install -Dm755 "$BASE_PATH/files/uci-defaults/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/usr/libexec/992_set-wifi-uci.sh"
        rm -f "$wifi_defaults_path"

        if ! grep -Fqx "$wifi_apply_line" "$wifi_detect_path"; then
            sed -i '/^[[:space:]]*\/sbin\/wifi config$/a\    /usr/libexec/992_set-wifi-uci.sh --hotplug' "$wifi_detect_path"
        fi

        if ! awk -v apply="$wifi_apply_line" '
            /^[[:space:]]*\/sbin\/wifi config$/ { config = NR }
            index($0, apply) { hook = NR; hooks++ }
            /^[[:space:]]*ubus call network\.wireless retry$/ { retry = NR }
            END { exit !(config && hooks == 1 && retry && config < hook && hook < retry) }
        ' "$wifi_detect_path"; then
            echo "错误：VIKINGYFY Wi-Fi 初始化钩子没有位于配置生成与无线 retry 之间。" >&2
            return 1
        fi
    else
        install -Dm544 "$BASE_PATH/files/uci-defaults/992_set-wifi-uci.sh" "$wifi_defaults_path"
    fi

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/files/misc/tempinfo" ]; then
            \cp -f "$BASE_PATH/files/misc/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}
