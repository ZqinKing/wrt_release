#!/usr/bin/env bash
# make defconfig 前后独立调用的配置修正。

remove_uhttpd_dependency() {
    local config_path="$BUILD_ROOT/.config"
    local luci_makefile_path="$BUILD_ROOT/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

sync_x86_64_distfeeds() {
    local distfeeds_path="$BUILD_ROOT/package/emortal/default-settings/files/99-distfeeds.conf"
    if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
        if [ -d "${distfeeds_path%/*}" ] && [ -f "$distfeeds_path" ]; then
            sed -i 's/aarch64_cortex-a53/x86_64/g' "$distfeeds_path"
        fi
    fi
}
