#!/usr/bin/env bash

# 预设变量（若外部未定义）
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
BASE_PATH="${BASE_PATH:-$(pwd)}"

fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        echo "设置默认主题为: ${THEME_SET:-argon}"
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-${THEME_SET:-argon}/g" {} +
    fi

    # 批量安装 uci-defaults 脚本
    local patches=("990_set_argon_primary" "991_custom_settings" "992_set-wifi-uci.sh")
    for p in "${patches[@]}"; do
        if [ -f "$BASE_PATH/patches/$p" ]; then
            install -Dm544 "$BASE_PATH/patches/$p" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/$p"
        fi
    done

    # 覆盖 tempinfo
    local temp_target="$BUILD_DIR/package/emortal/autocore/files/tempinfo"
    if [ -f "$temp_target" ] && [ -f "$BASE_PATH/patches/tempinfo" ]; then
        cp -f "$BASE_PATH/patches/tempinfo" "$temp_target"
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f "$CFG_PATH" ] && [ -n "$LAN_ADDR" ]; then
        echo "更新默认 LAN IP 为: $LAN_ADDR"
        # 更加精确地匹配 config_generate 中的 IP 赋值逻辑
        sed -i "s/192\.168\.[0-9]*\.1/$LAN_ADDR/g" "$CFG_PATH"
    fi
}

remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")

    echo "移除不必要的 NSS 相关内核模块..."
    for target_mk in "${target_mks[@]}"; do
        [ -f "$target_mk" ] && sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"
    done

    if [ -f "$ipq_mk_path" ]; then
        # 使用数组循环处理删除，保持代码整洁
        local nss_mods=(
            "kmod-qca-nss-drv-eogremgr" "kmod-qca-nss-drv-gre" "kmod-qca-nss-drv-map-t"
            "kmod-qca-nss-drv-match" "kmod-qca-nss-drv-mirror" "kmod-qca-nss-drv-tun6rd"
            "kmod-qca-nss-drv-tunipip6" "kmod-qca-nss-drv-vxlanmgr" "kmod-qca-nss-drv-wifi-meshmgr"
            "kmod-qca-nss-macsec"
        )
        for mod in "${nss_mods[@]}"; do
            sed -i "/$mod/d" "$ipq_mk_path"
        done
        sed -i -e 's/automount //g' -e 's/cpufreq //g' "$ipq_mk_path"
    fi
}

update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local url="https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile"

    if [ -d "$(dirname "$makefile")" ]; then
        echo "正在从远程同步 ath11k-firmware Makefile..."
        # 直接下载到目标位置，若失败则保留旧版本
        curl -fsSL --connect-timeout 10 -o "$makefile.tmp" "$url" && mv -f "$makefile.tmp" "$makefile" || echo "警告：下载 ath11k Makefile 失败，跳过。"
    fi
}

apply_passwall_tweaks() {
    # 清空内置中文字表（改用外部订阅）
    local chnlist_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    [ -f "$chnlist_path" ] && : > "$chnlist_path"

    # 优化 Xray 探测参数：增加 RTT 容忍度
    local xray_util_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        echo "配置自定义 OPKG Distfeeds..."
        # 写入配置
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        # 注入安装规则
        local make_file="$emortal_def_dir/Makefile"
        if ! grep -q "99-distfeeds.conf" "$make_file"; then
            sed -i "/define Package\/default-settings\/install/a \	\$(INSTALL_DIR) \$(1)/etc\n\	\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf" "$make_file"
        fi

        # 注入生效脚本逻辑
        local def_settings="$emortal_def_dir/files/99-default-settings"
        if [ -f "$def_settings" ] && ! grep -q "distfeeds.conf" "$def_settings"; then
            sed -i "/exit 0/i [ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\nsed -ri '/check_signature/s@^[^#]@#\&@' /etc/opkg.conf\n" "$def_settings"
        fi
    fi
}

set_nginx_default_config() {
    local nginx_util_dir="$BUILD_DIR/feeds/packages/net/nginx-util/files"
    
    # 优化默认 Server 配置（自签名证书 & 路径劫持）
    if [ -f "$nginx_util_dir/nginx.config" ]; then
        cat >"$nginx_util_dir/nginx.config" <<'EOF'
config main 'global'
	option uci_enable 'true'

config server '_lan'
	list listen '443 ssl default_server'
	list listen '[::]:443 ssl default_server'
	option server_name '_lan'
	list include 'restrict_locally'
	list include 'conf.d/*.locations'
	option uci_manage_ssl 'self-signed'
	option ssl_certificate '/etc/nginx/conf.d/_lan.crt'
	option ssl_certificate_key '/etc/nginx/conf.d/_lan.key'
	option ssl_session_cache 'shared:SSL:32k'
	option ssl_session_timeout '64m'
	option access_log 'off;'

config server 'http_only'
	list listen '80'
	list listen '[::]:80'
	option server_name 'http_only'
	list include 'conf.d/*.locations'
	option access_log 'off;'
EOF
    fi

    # 允许 Nginx 使用临时文件存储大 Body (解决部分上传问题)
    local template="$nginx_util_dir/uci.conf.template"
    if [ -f "$template" ] && ! grep -q "client_body_in_file_only" "$template"; then
        sed -i "/client_max_body_size/a \	client_body_in_file_only clean;\n\	client_body_temp_path /mnt/tmp;" "$template"
    fi
}

update_geoip() {
    # 切换为 geoip-only-cn-private 以节省空间并提高国内解析速度
    local geodata_path="$BUILD_DIR/package/feeds/small8/v2ray-geodata/Makefile"
    if [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F":=" '/GEOIP_VER/ {print $2}' "$geodata_path" | tr -d ' ')
        [ -z "$GEOIP_VER" ] && return 0
        
        local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
        local old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}')
        local new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}')

        if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
            sed -i "s|geoip.dat|geoip-only-cn-private.dat|g" "$geodata_path"
            sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
            echo "GeoIP 数据库已切换为 Lite 版。"
        fi
    fi
}
