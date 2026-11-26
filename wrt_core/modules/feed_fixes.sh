#!/usr/bin/env bash
# feed 软件包源码与依赖修正。

remove_unwanted_packages() {
    # 移除由 custom_feed 接管、冲突或含递归 Kconfig 的未用上游包。
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite" "luci-app-unblockneteasemusic" "luci-app-adguardhome"
        "luci-app-fwknopd"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria" "fwknop"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "open-app-filter" "msd_lite"
    )
    local packages_sound=("squeezelite")
    local packages_utils=(
        "cups"
    )
    for pkg in "${luci_packages[@]}"; do
        if [[ -d ./feeds/luci/applications/$pkg ]]; then
            \rm -rf ./feeds/luci/applications/$pkg
        fi
        if [[ -d ./feeds/luci/themes/$pkg ]]; then
            \rm -rf ./feeds/luci/themes/$pkg
        fi
    done

    for pkg in "${packages_net[@]}"; do
        if [[ -d ./feeds/packages/net/$pkg ]]; then
            \rm -rf ./feeds/packages/net/$pkg
        fi
    done

    for pkg in "${packages_sound[@]}"; do
        if [[ -d ./feeds/packages/sound/$pkg ]]; then
            \rm -rf ./feeds/packages/sound/$pkg
        fi
    done

    for pkg in "${packages_utils[@]}"; do
        if [[ -d ./feeds/packages/utils/$pkg ]]; then
            \rm -rf ./feeds/packages/utils/$pkg
        fi
    done

    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi

    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

update_lucky() {
    local lucky_repo_url="https://github.com/gdy666/luci-app-lucky.git"
    local target_custom_feed_dir="$(get_custom_feed_worktree_dir)"
    local lucky_dir="$target_custom_feed_dir/lucky"
    local luci_app_lucky_dir="$target_custom_feed_dir/luci-app-lucky"

    if [ ! -d "$lucky_dir" ] || [ ! -d "$luci_app_lucky_dir" ]; then
        echo "Warning: $lucky_dir 或 $luci_app_lucky_dir 不存在，跳过 lucky 源代码更新。" >&2
    else
        local tmp_dir
        tmp_dir=$(mktemp -d)

        echo "正在从 $lucky_repo_url 稀疏检出 luci-app-lucky 和 lucky..."

        if ! git_retry clone --depth 1 --filter=blob:none --no-checkout "$lucky_repo_url" "$tmp_dir"; then
            echo "错误：从 $lucky_repo_url 克隆仓库失败" >&2
            rm -rf "$tmp_dir"
            return 0
        fi

        pushd "$tmp_dir" >/dev/null
        git_retry sparse-checkout init --cone
        git_retry sparse-checkout set luci-app-lucky lucky || {
            echo "错误：稀疏检出 luci-app-lucky 或 lucky 失败" >&2
            popd >/dev/null
            rm -rf "$tmp_dir"
            return 0
        }
        git_retry checkout --quiet

        \cp -rf "$tmp_dir/luci-app-lucky/." "$luci_app_lucky_dir/"
        \cp -rf "$tmp_dir/lucky/." "$lucky_dir/"

        popd >/dev/null
        rm -rf "$tmp_dir"
        echo "luci-app-lucky 和 lucky 源代码更新完成。"
    fi

    local lucky_conf="$(get_custom_feed_worktree_dir)/lucky/files/luckyuci"
    if [ -f "$lucky_conf" ]; then
        sed -i "s/option enabled '1'/option enabled '0'/g" "$lucky_conf"
        sed -i "s/option logger '1'/option logger '0'/g" "$lucky_conf"
    fi

    local version
    version=$(find "$BASE_PATH/assets" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
    if [ -z "$version" ]; then
        echo "Warning: 未找到 lucky 补丁文件，跳过更新。" >&2
        return 0
    fi

    local makefile_path="$(get_custom_feed_worktree_dir)/lucky/Makefile"
    if [ ! -f "$makefile_path" ]; then
        echo "Warning: lucky Makefile not found. Skipping." >&2
        return 0
    fi

    echo "正在更新 lucky Makefile..."
    local patch_line="\\t[ -f \$(TOPDIR)/../wrt_core/assets/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../wrt_core/assets/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(DL_DIR)/\$(PKG_SOURCE)"

    if grep -q "Build/Prepare" "$makefile_path"; then
        sed -i "/Build\\/Prepare/a\\$patch_line" "$makefile_path"
        sed -i '/wget/d' "$makefile_path"
        echo "lucky Makefile 更新完成。"
    else
        echo "Warning: lucky Makefile 中未找到 'Build/Prepare'。跳过。" >&2
    fi
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

update_mosdns_deconfig() {
    local mosdns_conf="$(get_custom_feed_worktree_dir)/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

fix_netwiz_permissions() {
    local package_dir="$(get_custom_feed_worktree_dir)/luci-app-netwiz"
    local relative_path
    local executable_files=(
        root/usr/libexec/rpcd/netwiz root/usr/libexec/rpcd/netwiz_dev
        root/usr/libexec/netwiz-autodetect.sh root/usr/libexec/netwiz-monitor-loop.sh
        root/etc/init.d/netwiz-monitor root/etc/init.d/netwiz-recovery
        root/etc/init.d/netwiz-watchdog root/etc/hotplug.d/dhcp/99-netwiz-guard
    )

    for relative_path in "${executable_files[@]}"; do
        if [ ! -f "$package_dir/$relative_path" ]; then
            echo "错误：luci-app-netwiz 执行文件不存在：$package_dir/$relative_path" >&2
            return 1
        fi
        if ! chmod 755 "$package_dir/$relative_path"; then
            echo "错误：无法设置 luci-app-netwiz 执行权限：$package_dir/$relative_path" >&2
            return 1
        fi
    done
}

update_oaf_deconfig() {
    local init_path="$(get_custom_feed_worktree_dir)/open-app-filter/files/appfilter.init"

    if [ -f "$init_path" ]; then
        sed -i \
            -e '/config appfilter appfilter/,/config macfilter macfilter/ s/option enable 1/option enable 0/' \
            -e '/config macfilter macfilter/,/config record / s/option enable 1/option enable 0/' \
            -e "/config record 'record'/,/config network network/ s/option enable '1'/option enable '0'/" \
            "$init_path"

        sed -i \
            -e '/^[[:space:]]*ensure_default_configs$/a\
\tif [ "$(uci -q get fwx.appfilter.enable)" != "1" ] && [ "$(uci -q get fwx.macfilter.enable)" != "1" ] && [ "$(uci -q get fwx.record.enable)" != "1" ]; then' \
            -e '/^[[:space:]]*ensure_default_configs$/a\
\t\treturn 0' \
            -e '/^[[:space:]]*ensure_default_configs$/a\
\tfi' \
            "$init_path"
    fi
}

fix_easytier_mk() {
    local mk_path="$(get_custom_feed_worktree_dir)/luci-app-easytier/easytier/Makefile"
    if [ -f "$mk_path" ]; then
        sed -i 's/!@(mips||mipsel)/!TARGET_mips \&\& !TARGET_mipsel/g' "$mk_path"
    fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

fix_rust_compile_error() {
    local rust_makefile="$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    [ -f "$rust_makefile" ] || return 0

    sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$rust_makefile"

    if [[ "$REPO_URL" == "https://github.com/padavanonly/immortalwrt-mt798x-6.6.git" &&
          "$REPO_BRANCH" == "openwrt-24.10-6.6" ]]; then
        local rust_min_version="1.94.1"
        local rust_package_version
        local lowest_version
        rust_package_version=$(sed -n 's/^PKG_VERSION:=//p' "$rust_makefile")

        if [[ "$rust_package_version" == "1.94.0" ]]; then
            sed -i \
                -e 's/^PKG_VERSION:=1\.94\.0$/PKG_VERSION:=1.94.1/' \
                -e 's/^PKG_HASH:=.*/PKG_HASH:=174fce10ce012317ca995810296d8af199318838180b03d68a853e0f02d4b571/' \
                "$rust_makefile"
            rust_package_version=$(sed -n 's/^PKG_VERSION:=//p' "$rust_makefile")
        fi

        lowest_version=$(printf '%s\n' "$rust_min_version" "$rust_package_version" | sort -V | head -n 1)
        if [[ "$lowest_version" != "$rust_min_version" ]]; then
            echo "错误：padavanonly 源码需要 Rust $rust_min_version 或更新版本，当前 Rust 包版本为 $rust_package_version" >&2
            return 1
        fi
    fi
}

fix_cups_libcups_avahi_depends() {
    local makefile_path="$(get_custom_feed_worktree_dir)/cups/Makefile"

    # Check if file exists
    if [ ! -f "$makefile_path" ]; then
        echo "cups: libcups Makefile not found, skip: $makefile_path"
        return 0
    fi

    # Check if both deps already present within the libcups block only
    if sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi-client" && \
       sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi"; then
        echo "cups: libcups avahi deps already present, skip"
        return 0
    fi

    # Use scoped sed to modify DEPENDS only within Package/libcups block
    sed -i '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/ {
        /DEPENDS:=/ s/$/ +libavahi-client +libavahi/
    }' "$makefile_path"

    echo "cups: added missing avahi deps to Package/libcups"
    return 0
}

fix_easytier_lua() {
    local file_path="$(get_custom_feed_package_dir)/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then
        sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"
    fi
}
