#!/usr/bin/env bash
set -euo pipefail

read_target_ini() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$TARGET_INI"
}

kernel_vermagic=$(read_target_ini KERNEL_VERMAGIC)
kernel_modules=$(read_target_ini KERNEL_MODULES)

if [ -z "$kernel_vermagic" ]; then
    echo "fix_kernel_magic: KERNEL_VERMAGIC is empty; skipping"
    exit 0
fi

kernel_defaults="$BUILD_DIR/include/kernel-defaults.mk"
kernel_makefile="$BUILD_DIR/package/kernel/linux/Makefile"

if [ ! -f "$kernel_defaults" ]; then
    echo "fix_kernel_magic: missing $kernel_defaults" >&2
    exit 1
fi
if [ ! -f "$kernel_makefile" ]; then
    echo "fix_kernel_magic: missing $kernel_makefile" >&2
    exit 1
fi

sed -i "/\\$(LINUX_DIR)\/.vermagic$/c\	echo ${kernel_vermagic} > \\$(LINUX_DIR)/.vermagic" "$kernel_defaults"
sed -i "/STAMP_BUILT:=/c\  STAMP_BUILT:=\\$(STAMP_BUILT)_${kernel_vermagic}" "$kernel_makefile"

echo "fix_kernel_magic: kernel vermagic set to ${kernel_vermagic}"

if [ -n "$kernel_modules" ]; then
    uci_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults"
    mkdir -p "$uci_defaults_path"
    cat > "$uci_defaults_path/99-kmod-distfeeds.sh" <<EOF
#!/bin/sh
grep -qxF 'src/gz kmod ${kernel_modules}' /etc/opkg/distfeeds.conf || echo 'src/gz kmod ${kernel_modules}' >> /etc/opkg/distfeeds.conf
exit 0
EOF
    chmod 0755 "$uci_defaults_path/99-kmod-distfeeds.sh"
    echo "fix_kernel_magic: kmod distfeed set to ${kernel_modules}"
fi
