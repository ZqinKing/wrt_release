#!/usr/bin/env bash
# 构建树一致性检查。

verify_custom_feed_installed_paths() {
    local custom_feed_name
    local custom_feed_package_dir
    # install_feeds 后必须存在的 custom_feed 包路径。
    local required_package_dirs=(
        luci-app-adguardhome luci-app-mosdns v2ray-geodata luci-app-easytier
        luci-app-passwall nikki luci-app-nikki mihomo-meta luci-app-emmc-health
    )
    local missing_package_dirs=()

    custom_feed_name=$(get_custom_feed_name)
    custom_feed_package_dir=$(get_custom_feed_package_dir)

    collect_missing_directories "$custom_feed_package_dir" required_package_dirs missing_package_dirs

    if [ ${#missing_package_dirs[@]} -ne 0 ]; then
        printf '错误：%s 安装后缺少以下仓库依赖路径：\n' "$custom_feed_name" >&2
        printf '  - %s\n' "${missing_package_dirs[@]}" >&2
        return 1
    fi
}
