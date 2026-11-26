#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PROJECT="$WORK/project"
mkdir -p "$PROJECT/wrt_core" "$WORK/bin"
cp "$ROOT/build.sh" "$PROJECT/"
cp -a "$ROOT/wrt_core/compilecfg" "$ROOT/wrt_core/deconfig" "$ROOT/wrt_core/modules" "$PROJECT/wrt_core/"
export RECORD="$WORK/update-argument" MAKE_RECORD="$WORK/make-record"
export PATH="$WORK/bin:$PATH"

cat >"$PROJECT/wrt_core/update.sh" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$3" >"$RECORD"
build_dir=$3
[[ $build_dir == /* ]] || build_dir="$PWD/$build_dir"
mkdir -p "$build_dir/feeds/luci/collections/luci"
mkdir -p "$build_dir/package/emortal/default-settings/files"
printf 'LUCI_DEPENDS:=+luci-light\n' >"$build_dir/feeds/luci/collections/luci/Makefile"
printf 'aarch64_cortex-a53\n' >"$build_dir/package/emortal/default-settings/files/99-distfeeds.conf"
EOF
chmod +x "$PROJECT/wrt_core/update.sh"
cat >"$WORK/bin/make" <<'EOF'
#!/usr/bin/env bash
set -e
[[ $1 == defconfig ]]
cp .config "$MAKE_RECORD.config"
cp feeds/luci/collections/luci/Makefile "$MAKE_RECORD.luci"
cp package/emortal/default-settings/files/99-distfeeds.conf "$MAKE_RECORD.distfeeds"
EOF
chmod +x "$WORK/bin/make"

run_debug() {
    (cd "$PROJECT" && bash ./build.sh "$1" debug) >"$WORK/build.log" 2>&1
}

count=0
for ini in "$PROJECT"/wrt_core/compilecfg/*.ini; do
    device=$(basename "$ini" .ini)
    [[ -f "$PROJECT/wrt_core/deconfig/$device.config" ]] || continue
    run_debug "$device"
    if grep -Eq '^CONFIG_[A-Za-z0-9_-]+=[ymn]#' "$MAKE_RECORD.config"; then
        echo "FAIL: $device contains concatenated configuration lines" >&2
        grep -nE '^CONFIG_[A-Za-z0-9_-]+=[ymn]#' "$MAKE_RECORD.config" >&2
        exit 1
    fi
    count=$((count + 1))
done
echo "PASS: $count device configurations have valid append boundaries"

cat >"$PROJECT/wrt_core/compilecfg/fixture.ini" <<'EOF'
REPO_URL=https://example.invalid/source.git
REPO_BRANCH=main
BUILD_DIR=fixture-build
CONFIG_FRAGMENTS=fixture
EOF
printf 'CONFIG_TARGET_x86_64=y\nCONFIG_PACKAGE_luci-app-quickfile=y' >"$PROJECT/wrt_core/deconfig/fixture.config"
BASE=$(find "$PROJECT/wrt_core/deconfig" -name compile_base.config)
printf 'CONFIG_FIXTURE_BASE=y' >"$BASE"
printf 'CONFIG_FIXTURE_FRAGMENT=y' >"$PROJECT/wrt_core/deconfig/fragments/fixture.config"
run_debug fixture
grep -qx 'CONFIG_FIXTURE_BASE=y' "$MAKE_RECORD.config"
grep -qx 'CONFIG_FIXTURE_FRAGMENT=y' "$MAKE_RECORD.config"
[[ ! -s "$MAKE_RECORD.luci" ]]
grep -qx 'aarch64_cortex-a53' "$MAKE_RECORD.distfeeds"
grep -qx 'x86_64' "$PROJECT/fixture-build/package/emortal/default-settings/files/99-distfeeds.conf"
echo "PASS: fragments without trailing newlines and both defconfig hooks"

mkdir "$PROJECT/action_build"
(cd "$PROJECT/wrt_core" && bash ../build.sh fixture debug) >"$WORK/nested.log" 2>&1
[[ $(<"$RECORD") == "$PROJECT/action_build" ]]
[[ -f "$PROJECT/action_build/.config" ]]
echo "PASS: nested invocation resolves the root action_build directory"

ADD_CONFIG_FRAGMENTS=proxy REMOVE_CONFIG_FRAGMENTS=fixture \
    bash "$PROJECT/build.sh" fixture config_preview >"$WORK/preview.log"
grep -q 'Effective fragments: proxy' "$WORK/preview.log"
if (cd "$PROJECT" && ADD_CONFIG_FRAGMENTS=../invalid bash ./build.sh fixture config_preview) >"$WORK/invalid.log" 2>&1; then
    echo "FAIL: invalid fragment name accepted" >&2
    exit 1
fi
grep -q 'invalid config fragment name' "$WORK/invalid.log"
echo "PASS: fragment override and invalid-name boundaries"

rm -f "$RECORD"
mv "$BASE" "$BASE.saved"
for mode in config_preview container; do
    if (cd "$PROJECT" && bash ./build.sh fixture "$mode") >"$WORK/missing-$mode.log" 2>&1; then
        echo "FAIL: missing base configuration accepted in $mode mode" >&2
        exit 1
    fi
    grep -q 'Base config not found:' "$WORK/missing-$mode.log"
    [[ ! -e "$RECORD" ]]
done
echo "PASS: missing base configuration fails before preview or container work"
