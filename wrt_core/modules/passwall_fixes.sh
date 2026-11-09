#!/usr/bin/env bash
apply_passwall_smartdns_patches() {
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
    echo "已应用 PassWall SmartDNS custom.conf、UI cleanup、runtime 和 loop guard patch。"
}


apply_passwall_rules_tweaks() {
    local chnlist_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then
        >"$chnlist_path"
    fi
}


apply_passwall_xray_tweaks() {
    local xray_util_path="$(get_custom_feed_worktree_dir)/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
    fi
}


apply_passwall_fixes() {
    apply_passwall_smartdns_patches || return 1
    apply_passwall_rules_tweaks || return 1
    apply_passwall_xray_tweaks || return 1
}
