#!/usr/bin/env bash
# target、kernel 与 base system 源码修正。

is_vikingyfy_owrt_build() {
    [[ "${REPO_URL:-}" == "https://github.com/VIKINGYFY/immortalwrt.git" && "${REPO_BRANCH:-}" == "owrt" ]]
}


fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"
    local upstream_repo="https://github.com/immortalwrt/packages.git"
    local upstream_branch="openwrt-25.12"

    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        if ! sync_sparse_packages_to_feed_dir \
            "$upstream_repo" \
            "$upstream_branch" \
            "$BUILD_DIR/feeds/packages" \
            "immortalwrt/packages" \
            "net/miniupnpd"; then
            echo "错误：同步 miniupnpd 到 $upstream_branch 分支失败" >&2
            return 1
        fi

        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}


change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}


fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-openssl/wpad-mesh-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}


fix_kconfig_recursive_dependency() {
    local file="$BUILD_DIR/scripts/package-metadata.pl"
    if [ -f "$file" ]; then
        sed -i 's/<PACKAGE_\$pkgname/!=y/g' "$file"
        echo "已修复 package-metadata.pl 的 Kconfig 递归依赖生成逻辑。"
    fi
}


fix_nf_conntrack_bridge_package_split() {
    local netfilter_map="$BUILD_DIR/include/netfilter.mk"
    local netfilter_packages="$BUILD_DIR/package/kernel/linux/modules/netfilter.mk"
    local duplicate_map='nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE,'

    if [[ -f "$netfilter_map" && -f "$netfilter_packages" ]] &&
        grep -Fq "define KernelPackage/nf-conntrack-bridge" "$netfilter_packages" &&
        grep -Fq "$duplicate_map" "$netfilter_map"; then
        sed -i '/nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE,/d' "$netfilter_map"
        echo "已从 nft-bridge 分组移除重复的 nf_conntrack_bridge 模块映射。"
    fi
}


update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}


remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")

    for target_mk in "${target_mks[@]}"; do
        if [ -f "$target_mk" ]; then
            sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"
        fi
    done

    if [ -f "$ipq_mk_path" ]; then
        sed -i '/kmod-qca-nss-drv-eogremgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-gre/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-map-t/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-match/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-mirror/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tun6rd/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-tunipip6/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' "$ipq_mk_path"
        sed -i '/kmod-qca-nss-macsec/d' "$ipq_mk_path"

        sed -i 's/automount //g' "$ipq_mk_path"
        sed -i 's/cpufreq //g' "$ipq_mk_path"
    fi
}


update_affinity_script() {
    if is_vikingyfy_owrt_build; then
        echo "保留 VIKINGYFY owrt 原生 IRQ affinity。"
        return 0
    fi

    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}


fix_hash_value() {
    local makefile_path="$1"
    local old_hash="$2"
    local new_hash="$3"
    local package_name="$4"

    if [ -f "$makefile_path" ]; then
        sed -i "s/$old_hash/$new_hash/g" "$makefile_path"
        echo "已修正 $package_name 的哈希值。"
    fi
}


apply_hash_fixes() {
    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "860a816bf1e69d5a8a2049483197dbebe8a3da2c9b05b2da68c85ef7dee7bdde" \
        "582021891808442b01f551bc41d7d95c38fb00c1ec78a58ac3aaaf898fbd2b5b" \
        "smartdns"

    fix_hash_value \
        "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" \
        "320c99a65ca67a98d11a45292aa99b8904b5ebae5b0e17b302932076bf62b1ec" \
        "43e58467690476a77ce644f9dc246e8a481353160644203a1bd01eb09c881275" \
        "smartdns"
}


update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"
    local ipq60_target="$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk"
    local ipq807_target="$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk"

    # The recipe is SoC-specific rather than PPE-specific; use the updated owrt source for all builds.
    local url="https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/owrt/package/firmware/ath11k-firmware/Makefile"

    if [ -d "$(dirname "$makefile")" ]; then
        echo "正在更新 ath11k-firmware Makefile..."
        if ! curl_retry -fsSL -o "$new_mk" "$url"; then
            echo "错误：从 $url 下载 ath11k-firmware Makefile 失败" >&2
            exit 1
        fi
        if [ ! -s "$new_mk" ]; then
            echo "错误：下载的 ath11k-firmware Makefile 为空文件" >&2
            exit 1
        fi
        mv -f "$new_mk" "$makefile"

        if [ -f "$ipq60_target" ]; then
            sed -i 's/ath11k-firmware-ipq6018\([^-[:alnum:]_]\|$\)/ath11k-firmware-ipq6018-ddwrt\1/g' "$ipq60_target"
        fi

        if [ -f "$ipq807_target" ]; then
            sed -i 's/ath11k-firmware-ipq8074\([^-[:alnum:]_]\|$\)/ath11k-firmware-ipq8074-ddwrt\1/g' "$ipq807_target"
        fi

        if [ -f "$ipq60_target" ] || [ -f "$ipq807_target" ]; then
            echo "已同步 ipq60xx/ipq807x ath11k 固件依赖为 ddwrt 包名。"
        fi
    fi
}


change_cpuusage() {
    local luci_rpc_path="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local qualcommax_sbin_dir="$BUILD_DIR/target/linux/qualcommax/base-files/sbin"
    local filogic_sbin_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin"
    local cpuusage_script_command="/sbin/cpuusage"
    local ppe_aware_build=0

    if is_vikingyfy_owrt_build; then
        cpuusage_script_command="/sbin/cpuusage --ppe-nss"
        ppe_aware_build=1
    fi

    if [ -f "$luci_rpc_path" ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '${cpuusage_script_command}' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" "$luci_rpc_path"
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' "$luci_rpc_path"
        if [ "$ppe_aware_build" = "1" ] &&
            ! grep -Fq "const cpuUsageCommand = access('/sbin/cpuusage') ? '$cpuusage_script_command'" "$luci_rpc_path"; then
            echo "错误：VIKINGYFY LuCI getCPUUsage 未接入 PPE/NSS cpuusage 脚本。" >&2
            return 1
        fi
    elif [ "$ppe_aware_build" = "1" ]; then
        echo "错误：VIKINGYFY 构建缺少 LuCI cpuusage RPC 源文件：$luci_rpc_path" >&2
        return 1
    fi

    local old_script_path="$BUILD_DIR/package/base-files/files/sbin/cpuusage"
    if [ -f "$old_script_path" ]; then
        rm -f "$old_script_path"
    fi

    if [ -d "$BUILD_DIR/target/linux/qualcommax" ]; then
        install -Dm755 "$BASE_PATH/patches/cpuusage" "$qualcommax_sbin_dir/cpuusage"
    fi
    if [ -d "$BUILD_DIR/target/linux/mediatek" ]; then
        install -Dm755 "$BASE_PATH/patches/hnatusage" "$filogic_sbin_dir/cpuusage"
    fi
}


update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}


update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}


fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}


update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}


add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
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
