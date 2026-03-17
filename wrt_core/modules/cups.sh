#!/usr/bin/env bash

fix_cups_libcups_avahi_depends() {
    local BUILD_DIR="${BUILD_DIR:-$(pwd)}"
    local makefile_path="$BUILD_DIR/feeds/small8/cups/Makefile"
    
    # Check if file exists
    if [ ! -f "$makefile_path" ]; then
        echo "cups: libcups Makefile not found, skip: $makefile_path"
        return 0
    fi
    
    # Check if both deps already present within the libcups block only
    if sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi-client" && \
       sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi"; then
        echo "cups: libcups avahi deps already present, skip"
        return 0
    fi
    
    # Use scoped sed to modify DEPENDS only within Package/libcups block
    sed -i '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/ {
        /DEPENDS:=/ s/$/ +libavahi-client +libavahi/
    }' "$makefile_path"
    
    echo "cups: added missing avahi deps to Package/libcups"
    return 0
}
