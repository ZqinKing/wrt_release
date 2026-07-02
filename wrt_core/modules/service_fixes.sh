#!/usr/bin/env bash
# 服务包与运行时默认配置修正。

update_adguardhome() {
    local adguardhome_dir="$(get_custom_feed_package_dir)/luci-app-adguardhome"
    local repo_url="https://github.com/ZqinKing/luci-app-adguardhome.git"

    echo "正在更新 luci-app-adguardhome..."
    rm -rf "$adguardhome_dir" 2>/dev/null

    if ! git_retry clone --depth 1 "$repo_url" "$adguardhome_dir"; then
        echo "错误：从 $repo_url 克隆 luci-app-adguardhome 仓库失败" >&2
        exit 1
    fi
}


set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
START=99

boot() {
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
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


update_script_priority() {
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    local mosdns_path="$(get_custom_feed_package_dir)/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}


update_geoip() {
    local geodata_path="$(get_custom_feed_package_dir)/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            local old_SHA256
            if ! old_SHA256=$(wget_retry -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip.dat.sha256sum 获取旧的 geoip.dat 校验和失败" >&2
                return 1
            fi
            local new_SHA256
            if ! new_SHA256=$(wget_retry -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：从 $base_url/geoip-only-cn-private.dat.sha256sum 获取新的 geoip-only-cn-private.dat 校验和失败" >&2
                return 1
            fi
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}


fix_easytier_lua() {
    local file_path="$(get_custom_feed_package_dir)/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then
        sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"
    fi
}


fix_openssl_ktls() {
    local config_in="$BUILD_DIR/package/libs/openssl/Config.in"
    if [ -f "$config_in" ]; then
        echo "正在更新 OpenSSL kTLS 配置..."
        sed -i 's/select PACKAGE_kmod-tls/depends on PACKAGE_kmod-tls/g' "$config_in"
        sed -i '/depends on PACKAGE_kmod-tls/a\\tdefault y if PACKAGE_kmod-tls' "$config_in"
    fi
}


fix_opkg_check() {
    local patch_file="$BASE_PATH/patches/001-fix-provides-version-parsing.patch"
    local opkg_dir="$BUILD_DIR/package/system/opkg"
    if [ -f "$patch_file" ]; then
        install -Dm644 "$patch_file" "$opkg_dir/patches/001-fix-provides-version-parsing.patch"
    fi
}


fix_netfilter_kmod_clash() {
    local include_netfilter_mk="$BUILD_DIR/include/netfilter.mk"
    local netfilter_mk="$BUILD_DIR/package/kernel/linux/modules/netfilter.mk"

    if [ ! -f "$include_netfilter_mk" ]; then
        echo "Netfilter include file not found: $include_netfilter_mk" >&2
        return 1
    fi

    if [ ! -f "$netfilter_mk" ]; then
        echo "Netfilter makefile not found: $netfilter_mk" >&2
        return 1
    fi

    if grep -q 'CONFIG_IP_NF_IPTABLES_LEGACY, $(P_V4)ip_tables, ge 6.12' "$include_netfilter_mk" && \
       grep -q 'CONFIG_IP6_NF_IPTABLES_LEGACY, $(P_V6)ip6_tables, ge 6.12' "$include_netfilter_mk" && \
       grep -q 'DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables' "$netfilter_mk"; then
        echo "Netfilter kmod clash workaround already applied"
        return 0
    fi

    if grep -q '$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables),))' "$include_netfilter_mk"; then
        echo "Updating NF_IPT mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables),))@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables, lt 6.12),))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables, lt 6\.12)/a$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES_LEGACY, $(P_V4)ip_tables, ge 6.12),))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET)))' "$include_netfilter_mk"; then
        echo "Updating IPT_CORE userland mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET)))@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, lt 6.12)))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, lt 6\.12))/a$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES_LEGACY, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, ge 6.12)))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables),))' "$include_netfilter_mk"; then
        echo "Updating NF_IPT6 mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables),))@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables, lt 6.12),))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables, lt 6\.12)/a$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES_LEGACY, $(P_V6)ip6_tables, ge 6.12),))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6)))' "$include_netfilter_mk"; then
        echo "Updating IPT_IPV6 userland mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6)))@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6, lt 6.12)))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP6_NF_IPTABLES, ip6t_icmp6, lt 6\.12))/a$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES_LEGACY, ip6t_icmp6, ge 6.12)))' "$include_netfilter_mk"
    fi

    if grep -q 'DEPENDS:=+!LINUX_6_12:kmod-iptables' "$netfilter_mk"; then
        echo "Applying netfilter kmod clash workaround for Linux 6.12/6.18..."
        sed -i 's/DEPENDS:=+!LINUX_6_12:kmod-iptables/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/' "$netfilter_mk"
        return 0
    fi

    if grep -q 'DEPENDS:=+(!LINUX_6_12&&!LINUX_6_18):kmod-iptables' "$netfilter_mk"; then
        echo "Normalizing netfilter kmod clash workaround expression..."
        sed -i 's/DEPENDS:=+(!LINUX_6_12\&\&!LINUX_6_18):kmod-iptables/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/' "$netfilter_mk"
        return 0
    fi

    echo "Netfilter kmod clash workaround target not found in $netfilter_mk" >&2
    return 1
}


install_pbr_cmcc() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"

    if [ -d "$pbr_pkg_dir" ]; then
        echo "正在安装 PBR CMCC 配置文件..."
        install -Dm644 "$BASE_PATH/patches/pbr.user.cmcc" "$pbr_dir/pbr.user.cmcc"
        install -Dm644 "$BASE_PATH/patches/pbr.user.cmcc6" "$pbr_dir/pbr.user.cmcc6"

        if [ -f "$pbr_makefile" ]; then
            if ! grep -q "pbr.user.cmcc" "$pbr_makefile"; then
                echo "正在修改 PBR Makefile 添加安装规则..."
                sed -i '/pbr.user.netflix.*\$(1)/a\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc $(1)/usr/share/pbr/pbr.user.cmcc\
	$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc6 $(1)/usr/share/pbr/pbr.user.cmcc6' "$pbr_makefile"
            fi
        fi
    fi

    if [ -f "$pbr_conf" ]; then
        if ! grep -q "pbr.user.cmcc" "$pbr_conf"; then
            echo "正在添加 PBR CMCC 配置条目..."
            sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
                /option enabled '0'/a\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cmcc'\\
	option enabled '0'\\
\\
config include\\
	option path '/usr/share/pbr/pbr.user.cmcc6'\\
	option enabled '0'
            }" "$pbr_conf"
        fi
    fi
}


fix_pbr_ip_forward() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_init_script="$pbr_pkg_dir/files/etc/init.d/pbr"

    if [ ! -d "$pbr_pkg_dir" ]; then
        echo "PBR package directory not found: $pbr_pkg_dir"
        return 1
    fi

    if [ ! -f "$pbr_init_script" ]; then
        echo "PBR init script not found: $pbr_init_script"
        return 1
    fi

    # 已包含 enabled 判断时无需重复修正。
    if grep -q '\[ -n "$enabled" \] && \[ -n "$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward fix already applied"
        return 0
    fi

    # 上游代码已变化时直接跳过。
    if ! grep -q '\[ -n "$strict_enforcement" \] && \[ "$(cat /proc/sys/net/ipv4/ip_forward)"' "$pbr_init_script"; then
        echo "PBR IP Forward: 未找到需要修复的代码，可能上游已修复或此版本无此问题"
        return 0
    fi

    echo "正在应用 PBR IP Forward 修复..."
    # strict_enforcement 生效前先确认 pbr 已启用。
    sed -i 's/\[ -n "\$strict_enforcement" \] && \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/\[ -n "\$enabled" \] \&\& \[ -n "\$strict_enforcement" \] \&\& \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/' "$pbr_init_script"

    if grep -q '\[ -n "$enabled" \] && \[ -n "$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward 修复应用成功"
        return 0
    else
        echo "修复应用失败：未找到预期的修复内容"
        return 1
    fi
}

fix_quectel_cm() {
    local makefile_path="$BUILD_DIR/package/feeds/packages/quectel-cm/Makefile"
    local cmake_patch_path="$BUILD_DIR/package/feeds/packages/quectel-cm/patches/020-cmake.patch"

    if [ -f "$makefile_path" ]; then
        echo "正在修复 quectel-cm Makefile..."

        sed -i '/^PKG_SOURCE:=/d' "$makefile_path"
        sed -i '/^PKG_SOURCE_URL:=@IMMORTALWRT/d' "$makefile_path"
        sed -i '/^PKG_HASH:=/d' "$makefile_path"

        sed -i '/^PKG_RELEASE:=/a\
\
PKG_SOURCE_PROTO:=git\
PKG_SOURCE_URL:=https://github.com/Carton32/quectel-CM.git\
PKG_SOURCE_VERSION:=$(PKG_VERSION)\
PKG_MIRROR_HASH:=skip' "$makefile_path"

        sed -i 's/^PKG_RELEASE:=2$/PKG_RELEASE:=3/' "$makefile_path"

        echo "quectel-cm Makefile 修复完成。"
    fi

    if [ -f "$cmake_patch_path" ]; then
        sed -i 's/-cmake_minimum_required(VERSION 2\.4)$/-cmake_minimum_required(VERSION 2.4) /' "$cmake_patch_path"
        sed -i 's/project(quectel-CM)$/project(quectel-CM) /' "$cmake_patch_path"
    fi
}


set_nginx_default_config() {
    local nginx_config_path="$BUILD_DIR/feeds/packages/net/nginx-util/files/nginx.config"
    if [ -f "$nginx_config_path" ]; then
        cat >"$nginx_config_path" <<EOF
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
        option access_log 'off; # logd openwrt'

config server 'http_only'
        list listen '80'
        list listen '[::]:80'
        option server_name 'http_only'
        list include 'conf.d/*.locations'
        option access_log 'off; # logd openwrt'
EOF
    fi

    local nginx_template="$BUILD_DIR/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [ -f "$nginx_template" ]; then
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            sed -i "/client_max_body_size 128M;/a\\
\tclient_body_in_file_only clean;\\
\tclient_body_temp_path /mnt/tmp;" "$nginx_template"
        fi
    fi

    local luci_support_script="$BUILD_DIR/feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support"

    if [ -f "$luci_support_script" ]; then
        if ! grep -q "client_body_in_file_only off;" "$luci_support_script"; then
            echo "正在为 Nginx ubus location 配置应用修复..."
            sed -i "/ubus_parallel_req 2;/a\\        client_body_in_file_only off;\\n        client_max_body_size 1M;" "$luci_support_script"
        fi
    fi
}


update_uwsgi_limit_as() {
    local cgi_io_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"

    if [ -f "$cgi_io_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$cgi_io_ini"
    fi

    if [ -f "$webui_ini" ]; then
        sed -i 's/^limit-as = .*/limit-as = 8192/g' "$webui_ini"
    fi
}
