#!/usr/bin/env bash

set -e

collections_dir="$BUILD_DIR/feeds/luci/collections"

if [ -d "$collections_dir" ]; then
    find "$collections_dir" -type f -name "Makefile" -exec sed -i 's/luci-theme-bootstrap/luci-theme-fluent/g' {} \;
fi
