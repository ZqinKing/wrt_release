#!/usr/bin/env bash

set -e
set -o errexit
set -o errtrace

error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

trap 'error_handler' ERR

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4
TARGET_NAME=$5
TARGET_INI=$6

# 转换为绝对路径，避免后续 cd 后路径失效。
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="26.x"
LAN_ADDR="192.168.1.1"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
BASE_PATH=${BASE_PATH:-$SCRIPT_DIR}

# 按静态职责加载模块，执行顺序仍由本脚本统一控制。
source "$SCRIPT_DIR/modules/network.sh"
source "$SCRIPT_DIR/modules/repo.sh"
source "$SCRIPT_DIR/modules/feeds.sh"
source "$SCRIPT_DIR/modules/custom_feed.sh"
source "$SCRIPT_DIR/modules/verify.sh"
source "$SCRIPT_DIR/modules/docker.sh"
source "$SCRIPT_DIR/recipe.sh"
source "$SCRIPT_DIR/modules/cups.sh"
source "$SCRIPT_DIR/modules/feed_source_fixes.sh"
source "$SCRIPT_DIR/modules/package_source_updates.sh"
source "$SCRIPT_DIR/modules/target_fixes.sh"
source "$SCRIPT_DIR/modules/luci_fixes.sh"
source "$SCRIPT_DIR/modules/service_fixes.sh"

init_recipes() {
    if [[ -n "$TARGET_NAME" && -n "$TARGET_INI" ]]; then
        recipe_init "$TARGET_NAME" "$TARGET_INI" "$BUILD_DIR" "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH"
        recipe_print_plan
    fi
}

run_recipe_phase_if_enabled() {
    local phase="$1"
    if [[ -n "$TARGET_NAME" && -n "$TARGET_INI" ]]; then
        recipe_run_phase "$phase"
    fi
}

# 阶段顺序不可随意调整：feeds install 前后依赖的目录不同。
stage_repo_checkout() {
    # 从干净的上游源码树开始，保证后续修正基线一致。
    run_recipe_phase_if_enabled pre_clone
    clone_repo
    clean_up
    reset_feeds_conf
    run_recipe_phase_if_enabled post_clone
}

stage_upstream_feeds_update() {
    # 先生成上游 feeds/* 工作树。
    run_recipe_phase_if_enabled pre_feeds
    update_feeds
    run_recipe_phase_if_enabled post_feeds_update
}

stage_feed_source_cleanup() {
    # 清理会与 custom_feed 替换包冲突的上游 feed 包。
    remove_unwanted_packages
    remove_tweaked_packages
}

stage_custom_feed_prepare() {
    # custom_feed 以 src-link 加入 feeds，仍属于 install 前阶段。
    install_custom_feed
}

stage_pre_install_source_fixes() {
    # 这里仅修改源码树与 feeds/*，不能依赖 package/feeds/*。
    update_homeproxy
    fix_default_set
    fix_miniupnpd
    update_golang
    change_dnsmasq2full
    fix_mk_def_depends

    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    change_cpuusage
    update_tcping
    add_ax6600_led
    set_custom_task
    apply_passwall_tweaks
    update_nss_pbuf_performance
    set_build_signature
    update_nss_diag
    update_menu_location
    fix_compile_coremark
    update_dnsmasq_conf
    add_backup_info_to_sysupgrade
    update_mosdns_deconfig
    fix_quickstart
    update_oaf_deconfig
    add_timecontrol
    add_quickfile
    update_lucky
    fix_rust_compile_error
    update_smartdns
    update_diskman
    update_dockerman
    set_nginx_default_config
    update_uwsgi_limit_as
    update_nginx_ubus_module
    check_default_settings
    install_opkg_distfeeds
    fix_easytier_mk
    remove_attendedsysupgrade
    fix_kconfig_recursive_dependency
}

stage_feeds_install() {
    # install 后才会生成 package/feeds/*。
    install_feeds
    run_recipe_phase_if_enabled post_feeds_install
}

stage_post_install_package_fixes() {
    # 这里处理已安装到 package/feeds/* 的包和最终一致性检查。
    verify_custom_feed_installed_paths
    docker_stack_sync_nftables_compat "$BUILD_DIR" "0"
    fix_cups_libcups_avahi_depends
    fix_easytier_lua
    update_adguardhome
    update_script_priority
    update_geoip
    fix_openssl_ktls
    fix_opkg_check
    fix_netfilter_kmod_clash
    fix_quectel_cm
    install_pbr_cmcc
    fix_pbr_ip_forward
    # apply_hash_fixes
}

main() {
    init_recipes
    stage_repo_checkout
    stage_upstream_feeds_update
    stage_feed_source_cleanup
    stage_custom_feed_prepare
    stage_pre_install_source_fixes
    stage_feeds_install
    stage_post_install_package_fixes
}

main "$@"
