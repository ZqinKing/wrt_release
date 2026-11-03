#!/usr/bin/env bash
# install_feeds 前的 feed 工作树修正。

remove_unwanted_packages() {
    # 移除将由 custom_feed 接管或会产生冲突的上游包。
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite" "luci-app-unblockneteasemusic" "luci-app-adguardhome"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "open-app-filter" "msd_lite"
    )
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


update_homeproxy() {
    local repo_url="https://github.com/xchxtom/luci-app-homeproxy.git"
    local target_dir="$(get_custom_feed_worktree_dir)/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        echo "正在从 xchxtom 仓库更新 homeproxy..."
        rm -rf "$target_dir"
        if ! git clone --depth 1 "$repo_url" "$target_dir"; then
            echo "错误：从 $repo_url 克隆 homeproxy 仓库失败" >&2
            exit 1
        fi
    fi
}

update_singbox() {
    local target_dir="$(get_custom_feed_worktree_dir)/sing-box"
    # 容错：如果 feeds 体系尚未完全展开，尝试去本地源源目录寻找
    if [ ! -d "$target_dir" ]; then
        target_dir="$(get_custom_feed_source_dir)/sing-box"
    fi

    if [ -d "$target_dir" ]; then
        echo "正在将 sing-box 锁定编译为 1.14.4 版本..."
        local mk_path="$target_dir/Makefile"
        if [ -f "$mk_path" ]; then
            # 1. 强行修改 Makefile 中的版本号
            sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=1.14.4/g' "$mk_path"
            
            # 2. 动态获取并更新 sing-box 1.14.4 官方源码的 SHA256 哈希值（防止 OpenWrt 报错）
            echo "正在获取 sing-box v1.14.14 源码校验和..."
            local openwrt_tarball_url="https://codeload.github.com/SagerNet/sing-box/tar.gz/v1.14.4"
            local pkg_hash
            pkg_hash=$(curl -fsSL "$openwrt_tarball_url" | sha256sum | cut -d' ' -f1)
            
            if [ -n "$pkg_hash" ]; then
                sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$pkg_hash/g" "$mk_path"
                echo "sing-box 已成功锁定至 1.14.4，哈希值为: $pkg_hash"
            else
                # 如果网络波动获取失败，退化为 skip 跳过哈希校验（部分 OpenWrt 固件支持）
                echo "警告：未能获取 sing-box 源码哈希，尝试使用 skip 绕过" >&2
                sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/g" "$mk_path"
            fi
        fi
    else
        echo "警告：未找到 sing-box 源码目录，跳过版本锁定。" >&2
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
    version=$(find "$BASE_PATH/patches" -name "lucky_*.tar.gz" -printf "%f\n" | head -n 1 | sed -n 's/^lucky_\(.*\)_Linux.*$/\1/p')
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
    local patch_line="\\t[ -f \$(TOPDIR)/../wrt_core/patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 \$(TOPDIR)/../wrt_core/patches/lucky_${version}_Linux_\$(LUCKY_ARCH)_wanji.tar.gz \$(DL_DIR)/\$(PKG_SOURCE)"

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


fix_mkpkg_format_invalid() {
    local custom_feed_worktree_dir
    custom_feed_worktree_dir=$(get_custom_feed_worktree_dir)

    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f "$custom_feed_worktree_dir/v2ray-geodata/Makefile" ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' "$custom_feed_worktree_dir/v2ray-geodata/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-lib-taskd/Makefile" ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' "$custom_feed_worktree_dir/luci-lib-taskd/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-openclash/Makefile" ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-openclash/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-quickstart/Makefile" ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' "$custom_feed_worktree_dir/luci-app-quickstart/Makefile"
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-quickstart/Makefile"
        fi
        if [ -f "$custom_feed_worktree_dir/luci-app-store/Makefile" ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' "$custom_feed_worktree_dir/luci-app-store/Makefile"
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' "$custom_feed_worktree_dir/luci-app-store/Makefile"
        fi
    fi
}


update_tcping() {
    local tcping_path="$(get_custom_feed_worktree_dir)/tcping/Makefile"
    local url="https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/refs/heads/main/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ]; then
        echo "正在更新 tcping Makefile..."
        if ! curl_retry -fsSL -o "$tcping_path" "$url"; then
            echo "错误：从 $url 下载 tcping Makefile 失败" >&2
            exit 1
        fi
    fi
}


apply_passwall_smartdns_patch() {
    local package_dir="$(get_custom_feed_worktree_dir)/luci-app-passwall"
    local patch_files=(
        "$BASE_PATH/patches/passwall-smartdns-custom-conf.patch"
        "$BASE_PATH/patches/passwall-smartdns-ui-cleanup.patch"
        "$BASE_PATH/patches/passwall-smartdns-runtime.patch"
        "$BASE_PATH/patches/passwall-smartdns-loop-guard.patch"
    )
    local patch_file

    if [ ! -d "$package_dir" ]; then
        echo "错误：未找到 luci-app-passwall 源码目录：$package_dir" >&2
        return 1
    fi

    for patch_file in "${patch_files[@]}"; do
        if [ ! -f "$patch_file" ]; then
            echo "错误：未找到 Passwall patch：$patch_file" >&2
            return 1
        fi
        if ! (cd "$package_dir" && patch --dry-run --batch --fuzz=0 -p1 < "$patch_file" >/dev/null); then
            echo "错误：Passwall patch 无法应用，可能是上游源码已变化：$patch_file" >&2
            return 1
        fi
        if ! (cd "$package_dir" && patch --batch --fuzz=0 -p1 < "$patch_file" >/dev/null); then
            echo "错误：应用 Passwall patch 失败：$patch_file" >&2
            return 1
        fi
    done
    echo "已应用 Passwall SmartDNS custom.conf、UI cleanup、runtime 和 loop guard patch。"
}


apply_passwall_tweaks() {
    apply_passwall_smartdns_patch || return 1

    local chnlist_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi

    local xray_util_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}


update_mosdns_deconfig() {
    local mosdns_conf="$(get_custom_feed_worktree_dir)/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}


fix_quickstart() {
    local file_path="$(get_custom_feed_worktree_dir)/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    local makefile_path="$(get_custom_feed_worktree_dir)/quickstart/Makefile"
    local url="https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua"
    if [ -f "$file_path" ]; then
        echo "正在修复 quickstart..."
        if ! curl_retry -fsSL -o "$file_path" "$url"; then
            echo "错误：从 $url 下载 istore_backend.lua 失败" >&2
            exit 1
        fi
    fi

    if [ -f "$makefile_path" ]; then
        echo "正在移除 quickstart 非必要存储依赖..."
        sed -i \
            -e '/^[[:space:]]*DEPENDS:=/,/^[[:space:]]*URL:=/ s/[[:space:]]*+smartmontools-drivedb//g' \
            -e '/^[[:space:]]*DEPENDS:=/,/^[[:space:]]*URL:=/ s/[[:space:]]*+smartmontools//g' \
            -e '/^[[:space:]]*DEPENDS:=/,/^[[:space:]]*URL:=/ s/[[:space:]]*+mdadm//g' \
            -e '/^[[:space:]]*DEPENDS:=/,/^[[:space:]]*URL:=/ s/[[:space:]]*+parted//g' \
            -e '/^[[:space:]]*DEPENDS:=/,/^[[:space:]]*URL:=/ s/[[:space:]]*+e2fsprogs//g' \
            "$makefile_path"
    fi
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


remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}
