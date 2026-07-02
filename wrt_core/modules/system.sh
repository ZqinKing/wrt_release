#!/usr/bin/env bash
# 兼容旧入口，系统修正逻辑已拆入专用模块。

_MODULE_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$_MODULE_DIR/custom_feed.sh"
source "$_MODULE_DIR/feed_source_fixes.sh"
source "$_MODULE_DIR/target_fixes.sh"
source "$_MODULE_DIR/luci_fixes.sh"
source "$_MODULE_DIR/service_fixes.sh"
unset _MODULE_DIR
