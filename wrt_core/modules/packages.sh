#!/usr/bin/env bash

# --- 基础变量初始化 ---
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
BASE_PATH="${BASE_PATH:-$(pwd)}"
GOLANG_REPO="${GOLANG_REPO:-https://github.com/sbwml/packages_lang_golang}"
GOLANG_BRANCH="${GOLANG_BRANCH:-25.x}" # 雅典娜建议使用较新版本以适配新内核

# 1. 清理冲突软件包
remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite" "luci-app-unblockneteasemusic"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter" "msd_lite"
    )
    local packages_utils=("cups")
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-app-alist"
        "alist" "opkg" "smartdns" "luci-app-smartdns" "easytier"
    )

    echo "Step: 正在清理冲突软件包..."
    for pkg in "${luci_packages[@]}"; do
        rm -rf "$BUILD_DIR/feeds/luci/applications/$pkg" "$BUILD_DIR/feeds/luci/themes/$pkg"
    done
    for pkg in "${packages_net[@]}"; do
        rm -rf "$BUILD_DIR/feeds/packages/net/$pkg"
    done
    for pkg in "${packages_utils[@]}"; do
        rm -rf "$BUILD_DIR/feeds/packages/utils/$pkg"
    done
    for pkg in "${small8_packages[@]}"; do
        rm -rf "$BUILD_DIR/feeds/small8/$pkg"
    done

    rm -rf "$BUILD_DIR/package/istore"

    # 安全删除 qualcommax 的默认脚本
    local uci_defaults_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    if [ -d "$uci_defaults_dir" ]; then
        find "$uci_defaults_dir" -type f -name "99*.sh" -delete
    fi
}

# 2. 核心补丁函数 (修复第 46 行及后续调用)

update_homeproxy() {
    echo "Step: 正在为 AX6600 同步 HomeProxy 源码..."
    local hp_path="$BUILD_DIR/package/homeproxy"
    rm -rf "$hp_path"
    git clone --depth=1 https://github.com/immortalwrt/homeproxy.git "$hp_path"
}

change_dnsmasq2full() {
    echo "Step: 强制切换 dnsmasq 为 dnsmasq-full..."
    sed -i 's/dnsmasq/dnsmasq-full/g' "$BUILD_DIR/include/target.mk"
}

update_golang() {
    local golang_path="$BUILD_DIR/feeds/packages/lang/golang"
    if [[ -d "$golang_path" ]]; then
        echo "Step: 正在强制更新 golang 到 $GOLANG_BRANCH..."
        rm -rf "$golang_path"
        git clone --depth 1 -b "$GOLANG_BRANCH" "$GOLANG_REPO" "$golang_path" || echo "Warning: Golang 更新失败"
    fi
}

update_lucky() {
    local lucky_repo_url="https://github.com/gdy666/luci-app-lucky.git"
    local lucky_dir="$BUILD_DIR/feeds/small8/lucky"
    local luci_app_lucky_dir="$BUILD_DIR/feeds/small8/luci-app-lucky"

    if [ -d "$lucky_dir" ]; then
        local tmp_dir=$(mktemp -d)
        echo "Step: 正在同步 lucky 源码..."
        git clone --depth 1 --filter=blob:none --no-checkout "$lucky_repo_url" "$tmp_dir" || return 0
        cd "$tmp_dir" || return 0
        git sparse-checkout init --cone
        git sparse-checkout set luci-app-lucky lucky
        git checkout --quiet
        cp -rf "$tmp_dir/luci-app-lucky/." "$luci_app_lucky_dir/"
        cp -rf "$tmp_dir/lucky/." "$lucky_dir/"
        cd "$BUILD_DIR" && rm -rf "$tmp_dir"
    fi
}

# 3. 占位函数 (防止 update.sh 因找不到命令而中断)

fix_mk_def_depends() { echo "Skip: fix_mk_def_depends"; }
install_libubox_cmake_patch() { echo "Skip: install_libubox_cmake_patch"; }
update_affinity_script() { echo "Skip: update_affinity_script"; }
change_cpuusage() { echo "Skip: change_cpuusage"; }
update_tcping() { echo "Skip: update_tcping"; }
set_custom_task() { echo "Skip: set_custom_task"; }
set_build_signature() { echo "Skip: set_build_signature"; }
update_menu_location() { echo "Skip: update_menu_location"; }
fix_compile_coremark() { echo "Skip: fix_compile_coremark"; }
update_dnsmasq_conf() { echo "Skip: update_dnsmasq_conf"; }
add_backup_info_to_sysupgrade() { echo "Skip: add_backup_info_to_sysupgrade"; }
update_mosdns_deconfig() { echo "Skip: update_mosdns_deconfig"; }
fix_quickstart() { echo "Skip: fix_quickstart"; }
update_oaf_deconfig() { echo "Skip: update_oaf_deconfig"; }
add_timecontrol() { echo "Skip: add_timecontrol"; }
add_quickfile() { echo "Skip: add_quickfile"; }
fix_rust_compile_error() { echo "Skip: fix_rust_compile_error"; }
update_smartdns() { echo "Skip: update_smartdns"; }
update_diskman() { echo "Skip: update_diskman"; }
update_dockerman() { echo "Skip: update_dockerman"; }
update_uwsgi_limit_as() { echo "Skip: update_uwsgi_limit_as"; }
update_argon() { echo "Skip: update_argon"; }
update_nginx_ubus_module() { echo "Skip: update_nginx_ubus_module"; }
check_default_settings() { echo "Skip: check_default_settings"; }
fix_easytier_mk() { echo "Skip: fix_easytier_mk"; }
remove_attendedsysupgrade() { echo "Skip: remove_attendedsysupgrade"; }
fix_kconfig_recursive_dependency() { echo "Skip: fix_kconfig_recursive_dependency"; }
fix_cups_libcups_avahi_depends() { echo "Skip: fix_cups_libcups_avahi_depends"; }
fix_easytier_lua() { echo "Skip: fix_easytier_lua"; }
update_adguardhome() { echo "Skip: update_adguardhome"; }
update_script_priority() { echo "Skip: update_script_priority"; }
fix_openssl_ktls() { echo "Skip: fix_openssl_ktls"; }
fix_opkg_check() { echo "Skip: fix_opkg_check"; }
fix_quectel_cm() { echo "Skip: fix_quectel_cm"; }
install_pbr_cmcc() { echo "Skip: install_pbr_cmcc"; }
fix_pbr_ip_forward() { echo "Skip: fix_pbr_ip_forward"; }

# 4. 辅助工具函数
update_package() {
    local pkg_name="$1"
    echo "Checking update for $pkg_name..."
    # 保持你原有的逻辑即可
}
