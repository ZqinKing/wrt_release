#!/bin/sh

board_name=$(cat /tmp/sysinfo/board_name)
hotplug_mode=0
wifi_config_changed=0
[ "${1:-}" = "--hotplug" ] && hotplug_mode=1

wifi_radio_ready() {
	local radio=$1
	[ "$(uci -q get wireless.radio${radio}.type)" = "mac80211" ] &&
		[ "$(uci -q get wireless.default_radio${radio}.device)" = "radio${radio}" ]
}

configure_wifi() {
	local radio=$1
	local channel=$2
	local htmode=$3
	local txpower=$4
	local ssid=$5
	local key=$6
	local encryption=${7:-"psk2+ccmp"} # 新增 encryption 参数，如果为空则默认为 psk2+ccmp
	if [ "$hotplug_mode" = "1" ] && ! wifi_radio_ready "$radio"; then
		return 0
	fi
	local now_encryption=$(uci -q get wireless.default_radio${radio}.encryption)
	if [ -n "$now_encryption" ] && [ "$now_encryption" != "none" ]; then
		local now_ssid=$(uci -q get wireless.default_radio${radio}.ssid)
		local now_key=$(uci -q get wireless.default_radio${radio}.key)
		local use_local_defaults=0

		if [ "$now_encryption" = "$encryption" ] && [ "$now_key" = "$key" ]; then
			if [ "$now_ssid" = "OWRT" ]; then
				use_local_defaults=1
			elif [ "$(uci -q get router-tool.radio${radio}.defaults_done)" = "1" ]; then
				local default_hostname=$(uci -q get system.@system[0].hostname)
				local board_vendor=$(printf '%s\n' "${board_name%%,*}" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')
				default_hostname=${default_hostname:-"OWRT"}
				case "$now_ssid" in
					"$default_hostname-$board_vendor-2.4G"|\
					"$default_hostname-$board_vendor-5.2G"|\
					"$default_hostname-$board_vendor-5.8G"|\
					"$default_hostname-$board_vendor-6G")
						use_local_defaults=1
						;;
				esac
			fi
		fi

		[ "$use_local_defaults" = "1" ] || return 0
	fi
	uci -q batch <<EOF
set wireless.radio${radio}.channel="${channel}"
set wireless.radio${radio}.htmode="${htmode}"
set wireless.radio${radio}.mu_beamformer='1'
set wireless.radio${radio}.country='US'
set wireless.radio${radio}.txpower="${txpower}"
set wireless.radio${radio}.cell_density='0'
set wireless.radio${radio}.disabled='0'
set wireless.default_radio${radio}.ssid="${ssid}"
set wireless.default_radio${radio}.encryption="${encryption}"
set wireless.default_radio${radio}.key="${key}"
set wireless.default_radio${radio}.ieee80211k='1'
set wireless.default_radio${radio}.time_advertisement='2'
set wireless.default_radio${radio}.time_zone='CST-8'
set wireless.default_radio${radio}.bss_transition='1'
set wireless.default_radio${radio}.wnm_sleep_mode='1'
set wireless.default_radio${radio}.wnm_sleep_mode_no_keys='1'
EOF
	wifi_config_changed=1
}

configure_wifi7() {
	local radio=$1
	local channel=$2
	local htmode=$3
	local txpower=$4
	local ssid=$5
	local key=$6
	local encryption=${7:-"psk2"} # 新增 encryption 参数，如果为空则默认为 psk2
	if [ "$hotplug_mode" = "1" ] && ! wifi_radio_ready "$radio"; then
		return 0
	fi
	local now_encryption=$(uci -q get wireless.default_radio${radio}.encryption)
	local bandmode=$(uci -q get wireless.radio${radio}.band)
	if [ "$bandmode" = "6g" ] && [ "$now_encryption" = "$encryption" ]; then
		return 0
	fi
	if [ "$bandmode" != "6g" ] && [ -n "$now_encryption" ] && [ "$now_encryption" != "none" ]; then
		return 0
	fi
	uci -q batch <<EOF
set wireless.radio${radio}.channel="${channel}"
set wireless.radio${radio}.htmode="${htmode}"
set wireless.radio${radio}.disabled='0'
set wireless.radio${radio}.country='US'
set wireless.radio${radio}.sku_idx='0'
set wireless.radio${radio}.he_twt_responder='1'
set wireless.radio${radio}.cell_density='0'
set wireless.radio${radio}.txpower="${txpower}"
set wireless.radio${radio}.noscan='0'
set wireless.default_radio${radio}.ssid="${ssid}"
set wireless.default_radio${radio}.encryption="${encryption}"
set wireless.default_radio${radio}.key="${key}"
set wireless.default_radio${radio}.vif_txpower="${txpower}"
set wireless.default_radio${radio}.ieee80211k='1'
set wireless.default_radio${radio}.time_zone='CST-8'
set wireless.default_radio${radio}.bss_transition='1'
set wireless.default_radio${radio}.wmm='1'
EOF
	wifi_config_changed=1
	if [ "$bandmode" = "2g" ]; then
		uci -q batch <<EOF
set wireless.radio${radio}.legacy_rates='1'
set wireless.radio${radio}.sr_enable='1'
set wireless.radio${radio}.etxbfen='1'
EOF
	elif [ "$bandmode" = "5g" ]; then
		uci -q batch <<EOF
set wireless.radio${radio}.background_radar='0'
EOF
	elif [ "$bandmode" = "6g" ]; then
		uci -q batch <<EOF
set wireless.radio${radio}.lpi_enable='0'
EOF
	fi
}

jdc_ax1800_pro_wifi_cfg() {
	configure_wifi 0 149 HE80 20 'JDC_AX1800PRO_5G' '12345678'
	configure_wifi 1 1 HE20 20 'JDC_AX1800PRO' '12345678'
}

jdc_ax6600_wifi_cfg() {
	configure_wifi 0 149 HE80 22 'JDC_AX6600_5G1' '12345678'
	configure_wifi 1 1 HE20 22 'JDC_AX6600' '12345678'
	configure_wifi 2 44 HE160 23 'JDC_AX6600_5G2' '12345678'
}

redmi_ax5_wifi_cfg() {
	configure_wifi 0 149 HE80 20 'Redmi_AX5_5G' '12345678'
	configure_wifi 1 1 HE20 20 'Redmi_AX5' '12345678'
}

aliyun_ap8220_wifi_cfg() {
	configure_wifi 0 149 HE80 26 'Aliyun_AP8220_5G' '12345678'
	configure_wifi 1 1 HE20 23 'Aliyun_AP8220' '12345678'
}

cmcc_rax3000m_wifi_cfg() {
	configure_wifi 0 1 HE20 23 'CMCC_RAX3000M' '12345678'
	configure_wifi 1 44 HE160 25 'CMCC_RAX3000M_5G' '12345678'
}

redmi_ax6_wifi_cfg() {
	configure_wifi 0 149 HE80 22 'Redmi_AX6_5G' '12345678'
	configure_wifi 1 1 HE20 21 'Redmi_AX6' '12345678'
}

qihoo_360v6_wifi_cfg() {
	configure_wifi 0 1 HE80 20 'Qihoo_360V6' '12345678'
	configure_wifi 1 149 HE20 20 'Qihoo_360V6_5G' '12345678'
}

linksys_mx4x00_wifi_cfg() {
	configure_wifi 0 44 HE80 22 'Linksys_MX4X00_5G1' '12345678'
	configure_wifi 1 1 HE20 21 'Linksys_MX4X00' '12345678'
	configure_wifi 2 149 HE80 21 'Linksys_MX4X00_5G2' '12345678'
}

gemtek_w1701k_wifi_cfg() {
	configure_wifi7 0 1 EHT20 23 'Gemtek_W1701K' '12345678'
	configure_wifi7 1 44 EHT160 23 'Gemtek_W1701K_5G' '12345678'
	configure_wifi7 2 1 EHT320 23 'Gemtek_W1701K_6G' '12345678' 'sae'
	if [ "$hotplug_mode" != "1" ] || wifi_radio_ready 2; then
		uci set wireless.radio2.disabled='1'
		wifi_config_changed=1
	fi
}

link_nn6000_wifi_cfg() {
	configure_wifi 0 149 HE80 19 'Link_NN6000_5G' '12345678'
	configure_wifi 1 1 HT20 19 'Link_NN6000' '12345678'
}

zn_m2_wifi_cfg() {
	configure_wifi 0 149 HE80 19 'ZN_M2_5G' '12345678'
	configure_wifi 1 1 HT20 19 'ZN_M2' '12345678'
}

case "${board_name}" in
jdcloud,ax1800-pro | \
	jdcloud,re-ss-01)
	jdc_ax1800_pro_wifi_cfg
	;;
jdcloud,ax6600 | \
	jdcloud,re-cs-02)
	jdc_ax6600_wifi_cfg
	;;
zn,m2)
	zn_m2_wifi_cfg
	;;
redmi,ax5 | \
	redmi,ax5-jdcloud)
	redmi_ax5_wifi_cfg
	;;
aliyun,ap8220)
	aliyun_ap8220_wifi_cfg
	;;
cmcc,rax3000m)
	cmcc_rax3000m_wifi_cfg
	;;
redmi,ax6 | \
	redmi,ax6-stock)
	redmi_ax6_wifi_cfg
	;;
qihoo,360v6)
	qihoo_360v6_wifi_cfg
	;;
linksys,mx4200v1 | \
	linksys,mx4200v2 | \
	linksys,mx4300 | \
	linksys,homewrk)
	linksys_mx4x00_wifi_cfg
	;;
gemtek,w1701k-ubi)
	gemtek_w1701k_wifi_cfg
	;;
link,nn6000-v2)
	link_nn6000_wifi_cfg
	;;
*)
	exit 0
	;;
esac

if [ "$hotplug_mode" = "1" ]; then
	if [ "$wifi_config_changed" = "1" ]; then
		uci commit wireless
	fi
else
	uci commit wireless
	/etc/init.d/network restart
fi
