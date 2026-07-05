#!/usr/bin/env bash
set -euo pipefail

dest_dir="$BUILD_DIR/upx"
dest_bin="$dest_dir/upx"

mkdir -p "$dest_dir"

if [ -x "$dest_bin" ]; then
    echo "upx: using existing $dest_bin"
    exit 0
fi

if command -v upx >/dev/null 2>&1; then
    cp "$(command -v upx)" "$dest_bin"
    chmod +x "$dest_bin"
    echo "upx: copied system upx to $dest_bin"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "upx: curl is required to download UPX" >&2
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "upx: tar is required to extract UPX" >&2
    exit 1
fi

os=$(uname -s)
arch=$(uname -m)

case "$os" in
    Linux) upx_os="linux" ;;
    Darwin) upx_os="macos" ;;
    *)
        echo "upx: unsupported host OS '$os'" >&2
        exit 1
        ;;
esac

case "$arch" in
    x86_64|amd64) upx_arch="amd64" ;;
    aarch64|arm64) upx_arch="arm64" ;;
    *)
        echo "upx: unsupported host arch '$arch'" >&2
        exit 1
        ;;
esac

upx_tag=$(curl -fsSL https://api.github.com/repos/upx/upx/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$upx_tag" ]; then
    echo "upx: failed to detect latest UPX release" >&2
    exit 1
fi

upx_ver="${upx_tag#v}"
archive_name="upx-${upx_ver}-${upx_arch}_${upx_os}.tar.xz"
download_url="https://github.com/upx/upx/releases/download/${upx_tag}/${archive_name}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

curl -fL "$download_url" -o "$tmp_dir/upx.tar.xz"
tar -xf "$tmp_dir/upx.tar.xz" -C "$tmp_dir"

src_bin=$(find "$tmp_dir" -type f -name upx | head -n 1)
if [ -z "$src_bin" ] || [ ! -f "$src_bin" ]; then
    echo "upx: extracted archive did not contain an upx binary" >&2
    exit 1
fi

cp "$src_bin" "$dest_bin"
chmod +x "$dest_bin"
echo "upx: prepared $dest_bin from $download_url"
