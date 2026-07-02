#!/usr/bin/env bash
set -euo pipefail

tailscale_makefile=""
for candidate in \
    "$BUILD_DIR/package/feeds/small8/tailscale/Makefile" \
    "$BUILD_DIR/package/feeds/custom_feed/tailscale/Makefile" \
    "$BUILD_DIR/feeds/packages/net/tailscale/Makefile" \
    "$BUILD_DIR/feeds/custom_feed/tailscale/Makefile"; do
    if [ -f "$candidate" ]; then
        tailscale_makefile="$candidate"
        break
    fi
done

if [ -z "$tailscale_makefile" ]; then
    echo "tailscale_use_awg: tailscale Makefile not found; skipping"
    exit 0
fi

sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://codeload.github.com/LiuTangLei/tailscale/tar.gz/v$(PKG_VERSION)?|' "$tailscale_makefile"

if grep -q '^PKG_VERSION:=' "$tailscale_makefile"; then
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=1.92.3/' "$tailscale_makefile"
fi

source_url=$(awk -F= '$1 == "PKG_SOURCE_URL:" {print $2; exit}' "$tailscale_makefile")
source_name=$(awk -F= '$1 == "PKG_SOURCE:" {print $2; exit}' "$tailscale_makefile")
if [ -n "$source_name" ]; then
    source_url=${source_url//'$(PKG_VERSION)'/1.92.3}
    source_url=${source_url//'${PKG_VERSION}'/1.92.3}
    if hash_value=$(curl -fsSL "${source_url}${source_name}" | sha256sum | cut -b -64); then
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=${hash_value}/" "$tailscale_makefile"
    else
        echo "tailscale_use_awg: warning: failed to refresh PKG_HASH" >&2
    fi
fi

echo "tailscale_use_awg: patched $tailscale_makefile"
