#!/usr/bin/env bash
# ============================================================================
# 文件名: config_tweaks.sh
# 描述: 配置修改模块，集中管理原脚本中散落的 sed 替换逻辑
# 作者: ZqinKing
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"

# ============================================================================
# 设备配置应用（NSS 和代理配置）
# ============================================================================

# 应用设备配置文件
# 用法: apply_device_config [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为:
#   1. 复制设备基础配置文件到构建目录
#   2. 检测是否为 IPQ 平台，如果是则追加 NSS 配置
#   3. 追加代理配置
apply_device_config() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi
    
    # 如果没有指定设备配置，跳过
    if [[ -z "$CONF_DEVICE_CONFIG" || ! -f "$CONF_DEVICE_CONFIG" ]]; then
        log_info "未指定设备配置文件，跳过设备配置应用。"
        return 0
    fi
    
    local target_config="$build_dir/.config"
    
    log_info "正在应用设备配置: $CONF_DEVICE_CONFIG"
    
    # 复制基础配置文件
    try_run "cp -f \"$CONF_DEVICE_CONFIG\" \"$target_config\""
    
    # 检测是否为 IPQ 平台（ipq60xx 或 ipq807x）
    local is_ipq_platform=0
    if grep -qE "(ipq60xx|ipq807x)" "$target_config" 2>/dev/null; then
        is_ipq_platform=1
        log_info "检测到 IPQ 平台（ipq60xx/ipq807x）"
    fi
    
    # 检测是否配置了 GIT_MIRROR（如果配置了则不追加 NSS）
    local has_git_mirror=0
    if grep -q "CONFIG_GIT_MIRROR" "$target_config" 2>/dev/null; then
        has_git_mirror=1
        log_info "检测到 CONFIG_GIT_MIRROR 配置"
    fi
    
    # 如果是 IPQ 平台且没有 GIT_MIRROR，追加 NSS 配置
    if [[ $is_ipq_platform -eq 1 && $has_git_mirror -eq 0 ]]; then
        if [[ -n "$CONF_NSS_CONFIG" && -f "$CONF_NSS_CONFIG" ]]; then
            log_info "正在追加 NSS 配置: $CONF_NSS_CONFIG"
            try_run "cat \"$CONF_NSS_CONFIG\" >> \"$target_config\""
        else
            log_warn "NSS 配置文件不存在: $CONF_NSS_CONFIG"
        fi
    fi
    
    # 始终追加代理配置
    if [[ -n "$CONF_PROXY_CONFIG" && -f "$CONF_PROXY_CONFIG" ]]; then
        log_info "正在追加代理配置: $CONF_PROXY_CONFIG"
        try_run "cat \"$CONF_PROXY_CONFIG\" >> \"$target_config\""
    else
        log_warn "代理配置文件不存在: $CONF_PROXY_CONFIG"
    fi
    
    log_info "设备配置应用完成。"
}

# 移除 uhttpd 依赖
# 用法: remove_uhttpd_dependency [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为: 当启用 luci-app-quickfile 插件时，移除 luci 对 uhttpd 的依赖
remove_uhttpd_dependency() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi
    
    local config_path="$build_dir/.config"
    local luci_makefile_path="$build_dir/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path" 2>/dev/null; then
        if [[ -f "$luci_makefile_path" ]]; then
            try_run "sed -i '/luci-light/d' \"$luci_makefile_path\""
            log_info "已移除 uhttpd (luci-light) 依赖（因为启用了 luci-app-quickfile/nginx）"
        fi
    fi
}

# ============================================================================
# 系统级配置修改
# ============================================================================

# 应用系统级配置修改
# 用法: apply_system_tweaks [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为: 修改默认主题、LAN IP、dnsmasq 配置等系统级设置
apply_system_tweaks() {
    local build_dir="$1"
    
    # 设置默认主题
    if [[ -d "$build_dir/feeds/luci/collections/" ]]; then
        log_info "正在设置默认主题为 $CONF_THEME_SET..."
        find "$build_dir/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$CONF_THEME_SET/g" {} \;
    fi

    # 修改默认 LAN IP 地址
    local cfg_path="$build_dir/package/base-files/files/bin/config_generate"
    if [[ -f "$cfg_path" ]]; then
        log_info "正在设置默认 LAN IP 为 $CONF_LAN_ADDR..."
        try_run "sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$CONF_LAN_ADDR'/g' \"$cfg_path\""
    fi
    
    # 修改 dnsmasq 配置（移除 dns_redirect）
    local dnsmasq_conf="$build_dir/package/network/services/dnsmasq/files/dhcp.conf"
    if [[ -f "$dnsmasq_conf" ]]; then
        try_run "sed -i '/dns_redirect/d' \"$dnsmasq_conf\""
    fi
    
    # 将 dnsmasq 替换为 dnsmasq-full
    if ! grep -q "dnsmasq-full" "$build_dir/include/target.mk"; then
        log_info "正在切换到 dnsmasq-full..."
        try_run "sed -i 's/dnsmasq/dnsmasq-full/g' \"$build_dir/include/target.mk\""
    fi
    
    # 修复 Makefile 默认依赖
    try_run "sed -i 's/libustream-mbedtls/libustream-openssl/g' \"$build_dir/include/target.mk\" 2>/dev/null" 1
    if [[ -f "$build_dir/target/linux/qualcommax/Makefile" ]]; then
        try_run "sed -i 's/wpad-openssl/wpad-mesh-openssl/g' \"$build_dir/target/linux/qualcommax/Makefile\""
    fi
}

# ============================================================================
# 内核级配置修改
# ============================================================================

# 应用内核级配置修改
# 用法: apply_kernel_tweaks [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为: 移除不需要的 NSS 内核模块、修改 pbuf 性能配置等
apply_kernel_tweaks() {
    local build_dir="$1"
    
    # 移除特定的 NSS 内核模块
    local ipq_mk_path="$build_dir/target/linux/qualcommax/Makefile"
    local target_mks=("$build_dir/target/linux/qualcommax/ipq60xx/target.mk" "$build_dir/target/linux/qualcommax/ipq807x/target.mk")

    for target_mk in "${target_mks[@]}"; do
        if [[ -f "$target_mk" ]]; then
            try_run "sed -i 's/kmod-qca-nss-crypto//g' \"$target_mk\""
        fi
    done

    if [[ -f "$ipq_mk_path" ]]; then
        log_info "正在移除特定的 NSS 内核模块..."
        try_run "sed -i '/kmod-qca-nss-drv-eogremgr/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-gre/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-map-t/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-match/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-mirror/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-tun6rd/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-tunipip6/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-vxlanmgr/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' \"$ipq_mk_path\""
        try_run "sed -i '/kmod-qca-nss-macsec/d' \"$ipq_mk_path\""

        try_run "sed -i 's/automount //g' \"$ipq_mk_path\""
        try_run "sed -i 's/cpufreq //g' \"$ipq_mk_path\""
    fi
    
    # 修改 NSS pbuf 性能配置
    local pbuf_path="$build_dir/package/kernel/mac80211/files/pbuf.uci"
    if [[ -f "$pbuf_path" ]]; then
        try_run "sed -i \"s/auto_scale '1'/auto_scale 'off'/g\" \"$pbuf_path\""
        try_run "sed -i \"s/scaling_governor 'performance'/scaling_governor 'schedutil'/g\" \"$pbuf_path\""
    fi
    
    # 修复 OpenSSL kTLS 配置
    local config_in="$build_dir/package/libs/openssl/Config.in"
    if [[ -f "$config_in" ]]; then
        log_info "正在更新 OpenSSL kTLS 配置..."
        try_run "sed -i 's/select PACKAGE_kmod-tls/depends on PACKAGE_kmod-tls/g' \"$config_in\""
        try_run "sed -i '/depends on PACKAGE_kmod-tls/a\\\tdefault y if PACKAGE_kmod-tls' \"$config_in\""
    fi
}

# ============================================================================
# 应用级配置修改
# ============================================================================

# 应用应用级配置修改
# 用法: apply_app_tweaks [构建目录]
# 参数:
#   $1 - 构建目录路径
# 行为: 修改各种应用的默认配置、修复编译问题等
apply_app_tweaks() {
    local build_dir="$1"
    
    # 修复 coremark 编译问题
    local coremark_mk="$build_dir/feeds/packages/utils/coremark/Makefile"
    if [[ -f "$coremark_mk" ]]; then
        try_run "sed -i 's/mkdir \$/mkdir -p \$/g' \"$coremark_mk\""
    fi
    
    # 修复 Rust 编译错误
    local rust_mk="$build_dir/feeds/packages/lang/rust/Makefile"
    if [[ -f "$rust_mk" ]]; then
        try_run "sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' \"$rust_mk\""
    fi
    
    # 修改 mosdns 默认配置
    local mosdns_conf="$build_dir/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [[ -f "$mosdns_conf" ]]; then
        try_run "sed -i 's/8000/300/g' \"$mosdns_conf\""
        try_run "sed -i 's/5335/5336/g' \"$mosdns_conf\""
    fi
    
    # 修改 OAF（应用过滤）默认配置
    local oaf_conf="$build_dir/feeds/small8/open-app-filter/files/appfilter.config"
    if [[ -f "$oaf_conf" ]]; then
        try_run "sed -i -e \"s/record_enable '1'/record_enable '0'/g\" -e \"s/disable_hnat '1'/disable_hnat '0'/g\" -e \"s/auto_load_engine '1'/auto_load_engine '0'/g\" \"$oaf_conf\""
    fi
    
    local oaf_uci_def="$build_dir/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    if [[ -f "$oaf_uci_def" ]]; then
        try_run "sed -i '/\(disable_hnat\|auto_load_engine\)/d' \"$oaf_uci_def\""
    fi
    
    # 设置构建签名
    local sys_js="$build_dir/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [[ -f "$sys_js" ]]; then
        try_run "sed -i \"s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g\" \"$sys_js\""
    fi
    
    # 修改菜单位置
    local samba4_path="$build_dir/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [[ -f "$samba4_path" ]]; then
        try_run "sed -i 's/nas/services/g' \"$samba4_path\""
    fi

    local tailscale_path="$build_dir/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [[ -f "$tailscale_path" ]]; then
        try_run "sed -i 's/services/vpn/g' \"$tailscale_path\""
    fi
    
    # 修复 easytier Lua 脚本
    local easytier_lua="$build_dir/package/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [[ -f "$easytier_lua" ]]; then
        try_run "sed -i 's/util.pcdata/xml.pcdata/g' \"$easytier_lua\""
    fi
    
    # 修复 easytier Makefile
    local easytier_mk="$build_dir/feeds/small8/luci-app-easytier/easytier/Makefile"
    if [[ -f "$easytier_mk" ]]; then
        try_run "sed -i 's/!@(mips||mipsel)/!TARGET_mips \&\& !TARGET_mipsel/g' \"$easytier_mk\""
    fi
    
    # 修改 uwsgi 内存限制
    local cgi_io_ini="$build_dir/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$build_dir/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"
    if [[ -f "$cgi_io_ini" ]]; then
        try_run "sed -i 's/^limit-as = .*/limit-as = 8192/g' \"$cgi_io_ini\""
    fi
    if [[ -f "$webui_ini" ]]; then
        try_run "sed -i 's/^limit-as = .*/limit-as = 8192/g' \"$webui_ini\""
    fi
    
    # 移除 attendedsysupgrade 应用
    find "$build_dir/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            try_run "sed -i \"/luci-app-attendedsysupgrade/d\" \"$makefile\""
        fi
    done
    
    # 移除 tweaked 软件包
    local target_mk="$build_dir/include/target.mk"
    if [[ -f "$target_mk" ]]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            try_run "sed -i 's/DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)/g' \"$target_mk\""
        fi
    fi
    
    # 更新 nginx ubus 模块
    local nginx_mk="$build_dir/feeds/packages/net/nginx/Makefile"
    local source_date="2024-03-02"
    local source_version="564fa3e9c2b04ea298ea659b793480415da26415"
    local mirror_hash="92c9ab94d88a2fe8d7d1e8a15d15cfc4d529fdc357ed96d22b65d5da3dd24d7f"

    if [[ -f "$nginx_mk" ]]; then
        try_run "sed -i \"s/SOURCE_DATE:=2020-09-06/SOURCE_DATE:=$source_date/g\" \"$nginx_mk\""
        try_run "sed -i \"s/SOURCE_VERSION:=b2d7260dcb428b2fb65540edb28d7538602b4a26/SOURCE_VERSION:=$source_version/g\" \"$nginx_mk\""
        try_run "sed -i \"s/MIRROR_HASH:=515bb9d355ad80916f594046a45c190a68fb6554d6795a54ca15cab8bdd12fda/MIRROR_HASH:=$mirror_hash/g\" \"$nginx_mk\""
    fi
    
    # 修改 Passwall Xray 配置
    local xray_util="$build_dir/feeds/small8/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [[ -f "$xray_util" ]]; then
        try_run "sed -i 's/maxRTT = \"1s\"/maxRTT = \"2s\"/g' \"$xray_util\""
        try_run "sed -i 's/sampling = 3/sampling = 5/g' \"$xray_util\""
    fi
    
    # 清空 Passwall chnlist
    local chnlist_path="$build_dir/feeds/small8/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [[ -f "$chnlist_path" ]]; then
        try_run "truncate -s 0 \"$chnlist_path\""
    fi
    
    # 修改 CPU 使用率获取方式
    local luci_rpc_path="$build_dir/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    if [[ -f "$luci_rpc_path" ]]; then
        try_run "sed -i \"s#const fd = popen('top -n1 | awk \\\\\'/^CPU/ {printf(\\\"%d%\\\\\", 100 - \\\$8)}\\\\\'' )#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\\\'/^CPU/ {printf(\\\"%d%\\\\\", 100 - \\\$8)}\\\\\''#g\" \"$luci_rpc_path\""
        try_run "sed -i '/cpuUsageCommand/a \\\\t\\\\t\\\\tconst fd = popen(cpuUsageCommand);' \"$luci_rpc_path\""
    fi
    
    # 创建自定义定时任务脚本
    local custom_task_path="$build_dir/package/base-files/files/etc/init.d/custom_task"
    if [[ -d "$(dirname "$custom_task_path")" ]]; then
        cat <<'EOF' > "$custom_task_path"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存清理定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_watchdog 任务
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_watchdog 任务，每15分钟执行一次
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
        try_run "chmod +x \"$custom_task_path\""
    fi
    
    # 安装 opkg distfeeds 配置
    local emortal_def_dir="$build_dir/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    if [[ -d "$emortal_def_dir" ]]; then
        cat <<'EOF' > "$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF
        if [[ -f "$emortal_def_dir/Makefile" ]]; then
             try_run "sed -i \"/define Package\/default-settings\/install/a\\\\\\\\t\\\$(INSTALL_DIR) \\\$(1)/etc\\\\n\\\\t\\\$(INSTALL_DATA) ./files/99-distfeeds.conf \\\$(1)/etc/99-distfeeds.conf\\\\n\" \"$emortal_def_dir/Makefile\""
        fi
        if [[ -f "$emortal_def_dir/files/99-default-settings" ]]; then
             try_run "sed -i \"/exit 0/i\\\\[ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\\\\nsed -ri '/check_signature/s@^[^#]@#&@' /etc/opkg.conf\\\\n\" \"$emortal_def_dir/files/99-default-settings\""
        fi
    fi
    
    # 添加备份信息到 sysupgrade.conf
    local sysupgrade_conf="$build_dir/package/base-files/files/etc/sysupgrade.conf"
    if [[ -f "$sysupgrade_conf" ]]; then
        cat >> "$sysupgrade_conf" <<EOF
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
    
    # 设置 nginx 默认配置
    local nginx_config_path="$build_dir/feeds/packages/net/nginx-util/files/nginx.config"
    if [[ -f "$nginx_config_path" ]]; then
        cat > "$nginx_config_path" <<EOF
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
    
    # 修改 nginx 模板配置
    local nginx_template="$build_dir/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [[ -f "$nginx_template" ]]; then
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            try_run "sed -i \"/client_max_body_size 128M;/a\\\\\\\\tclient_body_in_file_only clean;\\\\\\\\tclient_body_temp_path /mnt/tmp;\" \"$nginx_template\""
        fi
    fi
    
    # 修改 luci-support 脚本
    local luci_support_script="$build_dir/feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support"
    if [[ -f "$luci_support_script" ]]; then
        if ! grep -q "client_body_in_file_only off;" "$luci_support_script"; then
            try_run "sed -i \"/ubus_parallel_req 2;/a\\\\        client_body_in_file_only off;\\\\n        client_max_body_size 1M;\" \"$luci_support_script\""
        fi
    fi
    
    # 更新脚本启动优先级
    local qca_drv_init="$build_dir/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [[ -f "$qca_drv_init" ]]; then
        try_run "sed -i 's/START=.*/START=88/g' \"$qca_drv_init\""
    fi
    local pbuf_init="$build_dir/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [[ -f "$pbuf_init" ]]; then
        try_run "sed -i 's/START=.*/START=89/g' \"$pbuf_init\""
    fi
    local mosdns_init="$build_dir/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [[ -f "$mosdns_init" ]]; then
        try_run "sed -i 's/START=.*/START=94/g' \"$mosdns_init\""
    fi
    
    # 修复 Hash 值
    local smartdns_mk="$build_dir/package/feeds/packages/smartdns/Makefile"
    if [[ -f "$smartdns_mk" ]]; then
        try_run "sed -i 's/860a816bf1e69d5a8a2049483197dbebe8a3da2c9b05b2da68c85ef7dee7bdde/582021891808442b01f551bc41d7d95c38fb00c1ec78a58ac3aaaf898fbd2b5b/g' \"$smartdns_mk\""
        try_run "sed -i 's/320c99a65ca67a98d11a45292aa99b8904b5ebae5b0e17b302932076bf62b1ec/43e58467690476a77ce644f9dc246e8a481353160644203a1bd01eb09c881275/g' \"$smartdns_mk\""
    fi
}

# ============================================================================
# 主入口函数
# ============================================================================

# 配置修改主函数
# 用法: apply_config_tweaks [构建目录]
# 参数:
#   $1 - 构建目录路径（可选，默认使用配置中的 CONF_BUILD_DIR）
# 行为: 依次应用系统级、内核级和应用级配置修改
apply_config_tweaks() {
    local build_dir="$1"
    
    if [[ -z "$build_dir" ]]; then
        build_dir="$CONF_BUILD_DIR"
    fi
    
    log_info "正在应用配置修改..."
    apply_system_tweaks "$build_dir"
    apply_kernel_tweaks "$build_dir"
    apply_app_tweaks "$build_dir"
}
