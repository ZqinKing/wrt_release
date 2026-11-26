#!/usr/bin/env bash
# 设备配置片段解析与最终 .config 装配。

parse_fragment_csv() {
    local csv=$1
    local output_array=$2
    local item
    local -n target_array="$output_array"

    target_array=()
    csv=${csv//[[:space:]]/}
    [[ -n $csv ]] || return 0

    IFS=',' read -r -a target_array <<< "$csv"
    for item in "${target_array[@]}"; do
        if [[ -z $item ]]; then
            echo "Error: empty config fragment name in '$csv'." >&2
            exit 1
        fi
        if [[ ! $item =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            echo "Error: invalid config fragment name '$item'." >&2
            exit 1
        fi
    done
}

fragment_in_list() {
    local fragment=$1
    shift
    local item
    for item in "$@"; do
        [[ $item == "$fragment" ]] && return 0
    done
    return 1
}

append_unique_fragment() {
    local fragment=$1
    local output_array=$2
    local -n target_array="$output_array"
    fragment_in_list "$fragment" "${target_array[@]}" && return 0
    target_array+=("$fragment")
}

validate_enable_fragment() {
    local fragment=$1
    local fragment_path="$CONFIG_FRAGMENT_DIR/$fragment.config"
    if [[ ! -f $fragment_path ]]; then
        echo "Error: config fragment not found: $fragment_path" >&2
        exit 1
    fi
}

join_fragments() {
    local IFS=','
    echo "$*"
}

resolve_config_fragments() {
    local fragment
    local candidate_fragments=()
    parse_fragment_csv "$(read_ini_by_key "CONFIG_FRAGMENTS")" DEFAULT_CONFIG_FRAGMENTS
    parse_fragment_csv "${ADD_CONFIG_FRAGMENTS:-}" ADD_CONFIG_FRAGMENT_LIST
    parse_fragment_csv "${REMOVE_CONFIG_FRAGMENTS:-}" REMOVE_CONFIG_FRAGMENT_LIST

    for fragment in "${DEFAULT_CONFIG_FRAGMENTS[@]}" "${ADD_CONFIG_FRAGMENT_LIST[@]}" "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; do
        validate_enable_fragment "$fragment"
    done
    for fragment in "${DEFAULT_CONFIG_FRAGMENTS[@]}" "${ADD_CONFIG_FRAGMENT_LIST[@]}"; do
        append_unique_fragment "$fragment" candidate_fragments
    done

    EFFECTIVE_CONFIG_FRAGMENTS=()
    for fragment in "${candidate_fragments[@]}"; do
        if ! fragment_in_list "$fragment" "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; then
            EFFECTIVE_CONFIG_FRAGMENTS+=("$fragment")
        fi
    done
    for fragment in "${REMOVE_CONFIG_FRAGMENT_LIST[@]}"; do
        if [[ $fragment == "nss" ]]; then
            echo "Warning: removing platform fragment 'nss' is high risk." >&2
        fi
    done
}

print_config_fragment_summary() {
    echo "Config fragments:"
    echo "  Device: $Dev"
    echo "  Default fragments: $(join_fragments "${DEFAULT_CONFIG_FRAGMENTS[@]}")"
    echo "  Add fragments: $(join_fragments "${ADD_CONFIG_FRAGMENT_LIST[@]}")"
    echo "  Remove fragments: $(join_fragments "${REMOVE_CONFIG_FRAGMENT_LIST[@]}")"
    echo "  Effective fragments: $(join_fragments "${EFFECTIVE_CONFIG_FRAGMENTS[@]}")"
}

print_config_preview() {
    print_config_fragment_summary
    echo "Config assembly order:"
    echo "  1) $CONFIG_FILE"
    echo "  2) $BASE_CONFIG_FILE"
    local order=3
    local fragment
    for fragment in "${EFFECTIVE_CONFIG_FRAGMENTS[@]}"; do
        echo "  $order) $CONFIG_FRAGMENT_DIR/$fragment.config"
        order=$((order + 1))
    done
}

apply_config() {
    local fragment
    \cp -f "$CONFIG_FILE" "$BUILD_ROOT/.config"
    printf '\n' >>"$BUILD_ROOT/.config"
    cat "$BASE_CONFIG_FILE" >>"$BUILD_ROOT/.config"
    for fragment in "${EFFECTIVE_CONFIG_FRAGMENTS[@]}"; do
        printf '\n' >>"$BUILD_ROOT/.config"
        cat "$CONFIG_FRAGMENT_DIR/$fragment.config" >>"$BUILD_ROOT/.config"
    done
}
