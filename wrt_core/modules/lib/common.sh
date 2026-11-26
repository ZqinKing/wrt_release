#!/usr/bin/env bash
# 共享路径、INI 与源码分支判断；加载时仅定义函数。

is_vikingyfy_owrt_build() {
    [[ "${REPO_URL:-}" == "https://github.com/VIKINGYFY/immortalwrt.git" && "${REPO_BRANCH:-}" == "owrt" ]]
}

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

get_repo_root() {
    (cd "$BASE_PATH/.." && pwd)
}

validate_runtime_files() {
    local file
    for file in uci-defaults/991_custom_settings uci-defaults/992_set-wifi-uci.sh \
        init.d/smp_affinity sbin/cpuusage sbin/hnatusage sbin/nss_diag.sh \
        pbr/pbr.user.cmcc pbr/pbr.user.cmcc6 misc/tempinfo; do
        if [[ ! -f "$BASE_PATH/files/$file" ]]; then
            echo "错误：运行时源文件不存在：$BASE_PATH/files/$file" >&2
            return 1
        fi
    done
}
