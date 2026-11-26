#!/usr/bin/env bash
# LuCI 标识、菜单与主题修正。

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}

update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$(get_custom_feed_worktree_dir)/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

update_vantage() {
    local repo_url="https://github.com/anothaDev/luci-theme-vantage.git"
    local dst_theme_path="$BUILD_DIR/feeds/luci/themes/luci-theme-vantage"
    local dst_app_path="$BUILD_DIR/feeds/luci/applications/luci-app-vantage"
    local tmp_dir
    local commit_hash
    tmp_dir=$(mktemp -d)

    echo "正在更新 Vantage 主题和 dashboard..."

    if ! git_retry clone --depth 1 "$repo_url" "$tmp_dir"; then
        echo "错误：从 $repo_url 克隆 Vantage 仓库失败" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    if [ ! -f "$tmp_dir/luci-theme-vantage/Makefile" ] ||
       [ ! -f "$tmp_dir/luci-app-vantage/Makefile" ] ||
       [ ! -f "$tmp_dir/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css" ] ||
       [ ! -d "$tmp_dir/luci-theme-vantage/ucode/template/themes/vantage" ]; then
        echo "错误：Vantage 仓库缺少预期的主题、运行时资源或 dashboard 包目录" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    commit_hash=$(git -C "$tmp_dir" rev-parse HEAD)
    echo "Vantage 最新提交: $commit_hash"

    if [ -d "$BUILD_DIR/feeds/luci/themes" ]; then
        find "$BUILD_DIR/feeds/luci/themes" -mindepth 1 -maxdepth 1 ! -name "luci-theme-vantage" -exec rm -rf -- {} +
    fi
    if [ -d "$BUILD_DIR/package/feeds/luci" ]; then
        find "$BUILD_DIR/package/feeds/luci" -mindepth 1 -maxdepth 1 -name "luci-theme-*" ! -name "luci-theme-vantage" -exec rm -rf -- {} +
    fi
    rm -rf "$dst_theme_path" "$dst_app_path"
    mkdir -p "$BUILD_DIR/feeds/luci/themes" "$BUILD_DIR/feeds/luci/applications"
    mv "$tmp_dir/luci-theme-vantage" "$dst_theme_path"
    mv "$tmp_dir/luci-app-vantage" "$dst_app_path"
    rm -rf "$tmp_dir"

    local compatibility_patch="$BASE_PATH/patches/luci-theme-vantage-bootstrap-migration.patch"
    if [[ "$REPO_URL" == "https://github.com/padavanonly/immortalwrt-mt798x-6.6.git" &&
          "$REPO_BRANCH" == "openwrt-24.10-6.6" ]]; then
        compatibility_patch="$BASE_PATH/patches/luci-theme-vantage-padavanonly-migration.patch"
    fi
    local boot_script_dir="$BUILD_DIR/package/base-files/files"
    if ! patch --batch --forward --fuzz=0 --dry-run -d "$boot_script_dir" -p1 < "$compatibility_patch" ||
       ! patch --batch --forward --fuzz=0 -d "$boot_script_dir" -p1 < "$compatibility_patch"; then
        echo "错误：无法应用 LuCI 主题配置迁移补丁" >&2
        return 1
    fi

    echo "Vantage 主题和 dashboard 更新完成"
}
