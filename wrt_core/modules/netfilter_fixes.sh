#!/usr/bin/env bash
# Netfilter 内核模块拆分与依赖兼容。

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

netfilter_kmod_clash_include_fixed() {
    local include_netfilter_mk="$1"

    grep -q 'CONFIG_IP_NF_IPTABLES_LEGACY, $(P_V4)ip_tables, ge 6.12' "$include_netfilter_mk" && \
        grep -q 'CONFIG_IP6_NF_IPTABLES_LEGACY, $(P_V6)ip6_tables, ge 6.12' "$include_netfilter_mk" && \
        grep -q 'CONFIG_IP_NF_IPTABLES_LEGACY, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, ge 6.12' "$include_netfilter_mk" && \
        grep -q 'CONFIG_IP6_NF_IPTABLES_LEGACY, ip6t_icmp6, ge 6.12' "$include_netfilter_mk"
}

fix_netfilter_kmod_clash() {
    local include_netfilter_mk="$BUILD_DIR/include/netfilter.mk"
    local netfilter_mk="$BUILD_DIR/package/kernel/linux/modules/netfilter.mk"

    if [ ! -f "$include_netfilter_mk" ]; then
        echo "Netfilter include file not found: $include_netfilter_mk" >&2
        return 1
    fi

    if [ ! -f "$netfilter_mk" ]; then
        echo "Netfilter makefile not found: $netfilter_mk" >&2
        return 1
    fi

    if netfilter_kmod_clash_include_fixed "$include_netfilter_mk" && \
       grep -q 'DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables' "$netfilter_mk"; then
        echo "Netfilter kmod clash workaround already applied"
        return 0
    fi

    if grep -q '$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables),))' "$include_netfilter_mk"; then
        echo "Updating NF_IPT mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables),))@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables, lt 6.12),))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP_NF_IPTABLES, $(P_V4)ip_tables, lt 6\.12)/a$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT,CONFIG_IP_NF_IPTABLES_LEGACY, $(P_V4)ip_tables, ge 6.12),))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET)))' "$include_netfilter_mk"; then
        echo "Updating IPT_CORE userland mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET)))@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, lt 6.12)))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP_NF_IPTABLES, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, lt 6\.12))/a$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_CORE,CONFIG_IP_NF_IPTABLES_LEGACY, xt_standard ipt_icmp xt_tcp xt_udp xt_comment xt_set xt_SET, ge 6.12)))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables),))' "$include_netfilter_mk"; then
        echo "Updating NF_IPT6 mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables),))@$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables, lt 6.12),))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP6_NF_IPTABLES, $(P_V6)ip6_tables, lt 6\.12)/a$(eval $(if $(NF_KMOD),$(call nf_add,NF_IPT6,CONFIG_IP6_NF_IPTABLES_LEGACY, $(P_V6)ip6_tables, ge 6.12),))' "$include_netfilter_mk"
    fi

    if grep -q '$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6)))' "$include_netfilter_mk"; then
        echo "Updating IPT_IPV6 userland mapping for Linux 6.12/6.18..."
        sed -i 's@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6)))@$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES, ip6t_icmp6, lt 6.12)))@' "$include_netfilter_mk"
        sed -i '/CONFIG_IP6_NF_IPTABLES, ip6t_icmp6, lt 6\.12))/a$(eval $(if $(NF_KMOD),,$(call nf_add,IPT_IPV6,CONFIG_IP6_NF_IPTABLES_LEGACY, ip6t_icmp6, ge 6.12)))' "$include_netfilter_mk"
    fi

    if grep -q 'DEPENDS:=+!LINUX_6_12:kmod-iptables' "$netfilter_mk"; then
        echo "Applying netfilter kmod clash workaround for Linux 6.12/6.18..."
        sed -i 's/DEPENDS:=+!LINUX_6_12:kmod-iptables/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/' "$netfilter_mk"
    fi

    if grep -q 'DEPENDS:=+(!LINUX_6_12&&!LINUX_6_18):kmod-iptables' "$netfilter_mk"; then
        echo "Normalizing netfilter kmod clash workaround expression..."
        sed -i 's/DEPENDS:=+(!LINUX_6_12\&\&!LINUX_6_18):kmod-iptables/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/' "$netfilter_mk"
    fi

    if grep -q 'DEPENDS:=+kmod-iptables' "$netfilter_mk"; then
        echo "Applying netfilter kmod clash workaround for Linux 6.12/6.18..."
        sed -i 's/DEPENDS:=+kmod-iptables/DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables/' "$netfilter_mk"
    fi

    if grep -q 'DEPENDS:=+(!(LINUX_6_12||LINUX_6_18)):kmod-iptables' "$netfilter_mk"; then
        if netfilter_kmod_clash_include_fixed "$include_netfilter_mk"; then
            return 0
        fi

        echo "Netfilter include clash workaround target not found in $include_netfilter_mk" >&2
        return 1
    fi

    if netfilter_kmod_clash_include_fixed "$include_netfilter_mk"; then
        echo "Netfilter kmod-iptables dependency target not present; include workaround already applied"
        return 0
    fi

    echo "Netfilter kmod clash workaround target not found in $netfilter_mk" >&2
    return 1
}
