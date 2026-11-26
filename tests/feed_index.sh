#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM=${1:?Usage: bash tests/feed_index.sh /path/to/sparse/immortalwrt}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "Real feed-index fixture: $WORK"
BUILD_DIR="$WORK/build"
BASE_PATH="$ROOT/wrt_core"
FEEDS_CONF=feeds.conf.default
export TOPDIR="$BUILD_DIR" NETWORK_RETRY_MAX=1 NETWORK_RETRY_DELAY=0
mkdir -p "$BUILD_DIR/feeds/luci" "$WORK/repos"
cp -a "$UPSTREAM/"{include,scripts,config,target,package,tools,toolchain,Makefile,rules.mk,Config.in} "$BUILD_DIR/"
mkdir -p "$BUILD_DIR/package/feeds"
cp "$ROOT/tests/fixtures/luci.mk" "$BUILD_DIR/feeds/luci/luci.mk"
touch "$BUILD_DIR/$FEEDS_CONF" "$BUILD_DIR/.config"
source "$BASE_PATH/modules/lib/network.sh"
source "$BASE_PATH/modules/lib/feed_sync.sh"
source "$BASE_PATH/modules/feeds.sh"
source "${CUSTOM_FEED_MODULE:-$BASE_PATH/modules/custom_feed.sh}"
source "$BASE_PATH/modules/verify.sh"
source "$BASE_PATH/modules/feed_fixes.sh"

make_package() {
    local name=$1 path=$2
    mkdir -p "$path"
    cat >"$path/Makefile" <<EOF
include \$(TOPDIR)/rules.mk
PKG_NAME:=$name
PKG_VERSION:=1
PKG_RELEASE:=1
include \$(INCLUDE_DIR)/package.mk
define Package/$name
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Untouched dependency fixture
endef
\$(eval \$(call BuildPackage,$name))
EOF
}

for name in homeproxy adguardhome emmc airoha tcping; do
    git init -q -b main "$WORK/repos/$name"
    case "$name" in
        homeproxy|adguardhome)
            cp "$ROOT/tests/fixtures/$name.Makefile" "$WORK/repos/$name/Makefile" ;;
        tcping)
            mkdir "$WORK/repos/tcping/tcping"
            cp "$ROOT/tests/fixtures/tcping.Makefile" "$WORK/repos/tcping/tcping/Makefile" ;;
        emmc) make_package luci-app-emmc-health "$WORK/repos/$name" ;;
        airoha) make_package luci-app-airoha-npu "$WORK/repos/$name" ;;
    esac
    git -C "$WORK/repos/$name" add .
    git -C "$WORK/repos/$name" -c user.name=QA -c user.email=qa@example.invalid commit -qm snapshot
done

git_retry() {
    local args=("$@") i name
    for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[$i]}" in
            https://github.com/immortalwrt/homeproxy.git) name=homeproxy ;;
            https://github.com/ZqinKing/luci-app-adguardhome.git) name=adguardhome ;;
            https://github.com/adminchenyu/eMMC-Health.git) name=emmc ;;
            https://github.com/rchen14b/luci-app-airoha-npu.git) name=airoha ;;
            https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git) name=tcping ;;
            https://*) echo "Unexpected network access: ${args[$i]}" >&2; return 1 ;;
            *) continue ;;
        esac
        args[$i]="file://$WORK/repos/$name"
    done
    git "${args[@]}"
}

eval "$(declare -f sync_sparse_packages_to_feed_dir | sed '1s/sync_sparse_packages_to_feed_dir/real_sparse_sync/')"
sync_sparse_packages_to_feed_dir() {
    if [[ $1 == https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git ]]; then
        real_sparse_sync "$@"
        return
    fi
    # Untouched external catalogs are dependency doubles; changed inputs are real.
    local target=$3 pkg
    shift 4
    for pkg in "$@"; do
        make_package "$pkg" "$target/$pkg"
        if [[ $pkg == cups ]]; then
            cp "$ROOT/tests/fixtures/cups.Makefile" "$target/$pkg/Makefile"
        fi
    done
    make_package luci-theme-vantage "$target/luci-theme-vantage"
    make_package luci-app-vantage "$target/luci-app-vantage"
}

cd "$BUILD_DIR"
install_custom_feed
cmp "$ROOT/tests/fixtures/homeproxy.Makefile" custom_feed/luci-app-homeproxy/Makefile
cmp "$ROOT/tests/fixtures/adguardhome.Makefile" custom_feed/luci-app-adguardhome/Makefile
cmp "$ROOT/tests/fixtures/tcping.Makefile" custom_feed/tcping/Makefile
git -C custom_feed/luci-app-homeproxy log -1 --format=%ct
git -C custom_feed/luci-app-adguardhome log -1 --format=%ct
for package in luci-app-homeproxy luci-app-adguardhome; do
    version=$(make -s -C "custom_feed/$package" --eval='qa-version:;@printf "%s\n" "$(PKG_SRC_VERSION)"' qa-version)
    hash=$(git -C "custom_feed/$package" rev-parse --short=7 HEAD)
    [[ $version == *"~$hash" ]]
    echo "PASS: $package LuCI build version uses Git revision $version"
done
echo "PASS: custom_feed imports all three actual source snapshots before indexing"

# Load the real stage definition without executing the update entrypoint.
source <(awk '/^stage_pre_install_source_fixes\(\) \{/,/^\}/' "${UPDATE_SCRIPT:-$BASE_PATH/update.sh}")
while read -r name; do
    [[ $name == fix_cups_libcups_avahi_depends ]] && continue
    eval "$name() { :; }"
done < <(declare -f stage_pre_install_source_fixes |
    awk '/^[[:space:]]+[a-z_][a-z0-9_]*;?$/ { gsub(/[[:space:];]/, ""); print }')
stage_pre_install_source_fixes
install_feeds
verify_custom_feed_installed_paths
for package in luci-app-homeproxy luci-app-adguardhome tcping; do
    grep -qx "Package: $package" feeds/custom_feed.index
done
awk '/^Package: / { on = ($2 == "libcups") } on && /^Depends:/ { print }' \
    feeds/custom_feed.index >"$WORK/libcups.depends"
cat "$WORK/libcups.depends"
grep -q '+libavahi-client' "$WORK/libcups.depends"
grep -Eq '(^|[[:space:]])\+libavahi([[:space:]]|$)' "$WORK/libcups.depends"
echo "PASS: real feed index includes the three packages and both libcups dependencies"
if [[ -n ${EVIDENCE_DIR:-} ]]; then
    mkdir -p "$EVIDENCE_DIR"
    cp -L feeds/custom_feed.index "$EVIDENCE_DIR/custom_feed.index"
    cp "$WORK/libcups.depends" "$EVIDENCE_DIR/libcups.depends"
fi
