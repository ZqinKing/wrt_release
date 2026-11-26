#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "Runtime fixture: $WORK"
BASE_PATH="$ROOT/wrt_core"
BUILD_DIR="$WORK/build"
REPO_URL=https://example.invalid/source.git
REPO_BRANCH=main
THEME_SET=vantage
source "$BASE_PATH/modules/lib/common.sh"
source "$BASE_PATH/modules/default_settings.sh"
source "$BASE_PATH/modules/target_fixes.sh"
source "$BASE_PATH/modules/service_fixes.sh"
validate_runtime_files

check_install() {
    cmp "$BASE_PATH/files/$1" "$BUILD_DIR/$2"
    [[ $(stat -c %a "$BUILD_DIR/$2") == "$3" ]]
}

mkdir -p "$BUILD_DIR/target/linux/qualcommax" "$BUILD_DIR/target/linux/mediatek"
mkdir -p "$BUILD_DIR/package/kernel/mac80211/files"
mkdir -p "$BUILD_DIR/package/feeds/packages/pbr"
mkdir -p "$BUILD_DIR/package/emortal/autocore/files"
touch "$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
touch "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
chmod 600 "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
fix_default_set
update_affinity_script
change_cpuusage
update_nss_diag
install_pbr_cmcc
check_install uci-defaults/991_custom_settings package/base-files/files/etc/uci-defaults/991_custom_settings 544
check_install uci-defaults/992_set-wifi-uci.sh package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh 544
check_install init.d/smp_affinity target/linux/qualcommax/base-files/etc/init.d/smp_affinity 755
check_install sbin/cpuusage target/linux/qualcommax/base-files/sbin/cpuusage 755
check_install sbin/hnatusage target/linux/mediatek/filogic/base-files/sbin/cpuusage 755
check_install sbin/nss_diag.sh package/kernel/mac80211/files/nss_diag.sh 755
check_install pbr/pbr.user.cmcc package/feeds/packages/pbr/files/usr/share/pbr/pbr.user.cmcc 644
check_install pbr/pbr.user.cmcc6 package/feeds/packages/pbr/files/usr/share/pbr/pbr.user.cmcc6 644
check_install misc/tempinfo package/emortal/autocore/files/tempinfo 600
echo "PASS: nine runtime files retain their installed content and modes"

REPO_URL=https://github.com/VIKINGYFY/immortalwrt.git
REPO_BRANCH=owrt
HOTPLUG="$BUILD_DIR/package/network/config/wifi-scripts/files/etc/hotplug.d/ieee80211/10-wifi-detect"
mkdir -p "$(dirname "$HOTPLUG")"
printf '/sbin/wifi config\nubus call network.wireless retry\n' >"$HOTPLUG"
fix_default_set
fix_default_set
check_install uci-defaults/992_set-wifi-uci.sh package/base-files/files/usr/libexec/992_set-wifi-uci.sh 755
[[ ! -e "$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh" ]]
[[ $(grep -Fc '/usr/libexec/992_set-wifi-uci.sh --hotplug' "$HOTPLUG") == 1 ]]
echo "PASS: owrt uses one executable libexec hook and removes the legacy hook"

mkdir "$WORK/core"
cp -a "$BASE_PATH/modules" "$WORK/core/modules"
cp "$BASE_PATH/update.sh" "$WORK/core/update.sh"
if bash "$WORK/core/update.sh" "$REPO_URL" "$REPO_BRANCH" "$WORK/never-cloned" none >"$WORK/missing.log" 2>&1; then
    echo "FAIL: missing runtime source accepted" >&2
    exit 1
fi
grep -q '运行时源文件不存在' "$WORK/missing.log"
[[ ! -e "$WORK/never-cloned" ]]
echo "PASS: missing runtime source fails before repository checkout"
