#!/usr/bin/env bash

# Recipe planner/runner for wrt_core.
# Recipe metadata is JSON-only and parsed with jq. Target compile configs remain INI.

RECIPE_PHASES=(
    pre_clone
    post_clone
    pre_feeds
    post_feeds_update
    post_feeds_install
    pre_defconfig
    post_defconfig
    finalize
)

RECIPE_PLAN=()
RECIPE_TARGET_NAME=""
RECIPE_TARGET_INI=""
RECIPE_REPO_URL=""
RECIPE_REPO_BRANCH=""
RECIPE_BUILD_DIR=""
RECIPE_TARGET_TAGS=""
RECIPE_BASE_PATH=""

recipe_die() {
    echo "recipe: $*" >&2
    return 1
}

recipe_log_boundary() {
    local position="$1"
    local phase="$2"
    local name="$3"

    printf 'recipe: ===== %s recipe=%s phase=%s =====\n' "$position" "$name" "$phase"
}

recipe_trim() {
    local value="$*"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s' "$value"
}

recipe_target_ini_get() {
    local file="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

recipe_split_csv() {
    local raw="$1"
    local item
    local old_ifs="$IFS"

    IFS=','
    for item in $raw; do
        item=$(recipe_trim "$item")
        if [ -n "$item" ]; then
            printf '%s\n' "$item"
        fi
    done
    IFS="$old_ifs"
}

recipe_require_jq() {
    command -v jq >/dev/null 2>&1 || recipe_die "jq is required to read recipe.json"
}

recipe_phase_rank() {
    local phase="$1"
    local index
    for index in "${!RECIPE_PHASES[@]}"; do
        if [ "${RECIPE_PHASES[$index]}" = "$phase" ]; then
            printf '%s\n' "$index"
            return 0
        fi
    done
    return 1
}

recipe_dir() {
    local name="$1"
    printf '%s/recipes/%s\n' "$RECIPE_BASE_PATH" "$name"
}

recipe_json_path() {
    local name="$1"
    printf '%s/recipe.json\n' "$(recipe_dir "$name")"
}

recipe_json_get() {
    local file="$1"
    local expr="$2"
    jq -er "$expr" "$file"
}

recipe_json_get_optional() {
    local file="$1"
    local expr="$2"
    jq -er "$expr" "$file" 2>/dev/null || true
}

recipe_json_lines() {
    local file="$1"
    local expr="$2"
    jq -r "$expr" "$file"
}

recipe_json_object_get() {
    local json="$1"
    local expr="$2"
    printf '%s\n' "$json" | jq -er "$expr"
}

recipe_json_object_get_optional() {
    local json="$1"
    local expr="$2"
    printf '%s\n' "$json" | jq -er "$expr" 2>/dev/null || true
}

recipe_validate_structure() {
    local file="$1"

    jq -e '
        (.name | type == "string" and length > 0) and
        (.description | type == "string") and
        (.enabled | type == "boolean") and
        ((has("priority") | not) or (.priority == null) or (.priority | type == "number")) and
        (.phase | type == "string" and length > 0) and
        (.depends | type == "array") and
        (.conflicts | type == "array") and
        (.tags | type == "array") and
        (.when | type == "object") and
        (.when.targets | type == "array") and
        (.when.repo | type == "array") and
        (.when.branch | type == "array") and
        (.when.tags | type == "array") and
        (.actions | type == "object") and
        (.actions.addFeeds | type == "array") and
        (.actions.removeFeeds | type == "array") and
        ((.actions.importPackagesRegistry == null) or (.actions.importPackagesRegistry | type == "object")) and
        (.actions.importPackages | type == "array") and
        (.actions.removePackageDirs | type == "array") and
        (.actions.patches | type == "array") and
        (.actions.files | type == "array") and
        (.actions.configs | type == "array") and
        ((.actions.script | type == "string") or (.actions.script == null)) and
        all(.depends[]?; type == "string") and
        all(.conflicts[]?; type == "string") and
        all(.tags[]?; type == "string") and
        all(.when.targets[]?; type == "string") and
        all(.when.repo[]?; type == "string") and
        all(.when.branch[]?; type == "string") and
        all(.when.tags[]?; type == "string") and
        all(.actions.addFeeds[]?; type == "string") and
        all(.actions.removeFeeds[]?; type == "string") and
        all(.actions.importPackagesRegistry[]?; (.gitUrl | type == "string" and length > 0) and ((has("branch") | not) or (.branch == null) or (.branch | type == "string")) and ((has("sparseRoot") | not) or (.sparseRoot == null) or (.sparseRoot | type == "string"))) and
        all(.actions.importPackages[]?; type == "object" and (.source | type == "string" and length > 0) and (.name | type == "string" and length > 0) and ((has("target") | not) or (.target | type == "string" and length > 0))) and
        all(.actions.removePackageDirs[]?; type == "string") and
        all(.actions.patches[]?; type == "object" and (.source | type == "string" and length > 0) and (.target | type == "string" and length > 0) and ((has("mode") | not) or (.mode | type == "string" and test("^[0-7]{3,4}$")))) and
        all(.actions.files[]?; type == "object" and (.source | type == "string" and length > 0) and (.target | type == "string" and length > 0) and ((has("mode") | not) or (.mode | type == "string" and test("^[0-7]{3,4}$")))) and
        all(.actions.configs[]?; type == "string")
    ' "$file" >/dev/null || recipe_die "invalid recipe.json structure: $file"
}

recipe_validate_global_registry() {
    local registry="$RECIPE_BASE_PATH/recipes/import_registry.json"

    [ -f "$registry" ] || recipe_die "IMPORT_PACKAGES registry not found: $registry"
    jq -e '(.sources | type == "object") and all(.sources[]; (.gitUrl | type == "string" and length > 0) and ((has("branch") | not) or (.branch == null) or (.branch | type == "string")) and ((has("sparseRoot") | not) or (.sparseRoot == null) or (.sparseRoot | type == "string")))' "$registry" >/dev/null || recipe_die "invalid IMPORT_PACKAGES registry: $registry"
}

recipe_has_name() {
    local name="$1"
    local current
    for current in "${RECIPE_PLAN[@]}"; do
        if [ "$current" = "$name" ]; then
            return 0
        fi
    done
    return 1
}

recipe_append_unique_name() {
    local name="$1"
    if ! recipe_has_name "$name"; then
        RECIPE_PLAN+=("$name")
    fi
}

recipe_match_json_array() {
    local file="$1"
    local expr="$2"
    local actual="$3"
    local item
    local has_items=0

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        has_items=1
        if [ "$item" = "$actual" ]; then
            return 0
        fi
    done < <(recipe_json_lines "$file" "$expr")

    [ "$has_items" -eq 0 ]
}

recipe_match_json_tags() {
    local file="$1"
    local expr="$2"
    local wanted
    local tag
    local has_items=0

    while IFS= read -r wanted; do
        [ -n "$wanted" ] || continue
        has_items=1
        while IFS= read -r tag; do
            if [ "$wanted" = "$tag" ]; then
                return 0
            fi
        done < <(recipe_split_csv "$RECIPE_TARGET_TAGS")
    done < <(recipe_json_lines "$file" "$expr")

    [ "$has_items" -eq 0 ]
}

recipe_scan_initial_plan() {
    local recipe_json
    local name
    local enabled
    local target_recipes
    local disabled

    RECIPE_PLAN=()

    for recipe_json in "$RECIPE_BASE_PATH"/recipes/*/recipe.json; do
        [ -f "$recipe_json" ] || continue
        recipe_validate_structure "$recipe_json"
        name=$(basename "$(dirname "$recipe_json")")
        enabled=$(recipe_json_lines "$recipe_json" '.enabled')
        if [ "$enabled" = "true" ]; then
            recipe_append_unique_name "$name"
        fi
    done

    target_recipes=$(recipe_target_ini_get "$RECIPE_TARGET_INI" RECIPES)
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        recipe_append_unique_name "$name"
    done < <(recipe_split_csv "$target_recipes")

    disabled=$(recipe_target_ini_get "$RECIPE_TARGET_INI" DISABLE_RECIPES)
    if [ -n "$disabled" ]; then
        local next=()
        local current
        local disabled_name
        for current in "${RECIPE_PLAN[@]}"; do
            local keep=1
            while IFS= read -r disabled_name; do
                if [ "$current" = "$disabled_name" ]; then
                    keep=0
                    break
                fi
            done < <(recipe_split_csv "$disabled")
            if [ "$keep" -eq 1 ]; then
                next+=("$current")
            fi
        done
        RECIPE_PLAN=("${next[@]}")
    fi
}

recipe_validate_one() {
    local name="$1"
    local file
    local declared
    local phase

    file=$(recipe_json_path "$name")
    [ -f "$file" ] || recipe_die "missing recipe.json for '$name'"
    recipe_validate_structure "$file"

    declared=$(recipe_json_get "$file" '.name')
    [ "$declared" = "$name" ] || recipe_die "$name: name must equal directory name"

    phase=$(recipe_json_get "$file" '.phase')
    recipe_phase_rank "$phase" >/dev/null || recipe_die "$name: invalid phase '$phase'"

    recipe_match_json_array "$file" '.when.targets[]?' "$RECIPE_TARGET_NAME" || return 2
    recipe_match_json_array "$file" '.when.repo[]?' "$RECIPE_REPO_URL" || return 2
    recipe_match_json_array "$file" '.when.branch[]?' "$RECIPE_REPO_BRANCH" || return 2
    recipe_match_json_tags "$file" '.when.tags[]?' || return 2
}

recipe_resolve_depends() {
    local changed=1
    local name
    local dep
    local file

    while [ "$changed" -eq 1 ]; do
        changed=0
        for name in "${RECIPE_PLAN[@]}"; do
            file=$(recipe_json_path "$name")
            [ -f "$file" ] || recipe_die "missing recipe.json for '$name'"
            while IFS= read -r dep; do
                [ -n "$dep" ] || continue
                if ! recipe_has_name "$dep"; then
                    recipe_append_unique_name "$dep"
                    changed=1
                fi
            done < <(recipe_json_lines "$file" '.depends[]?')
        done
    done
}

recipe_filter_conditions() {
    local next=()
    local name
    local status

    for name in "${RECIPE_PLAN[@]}"; do
        set +e
        recipe_validate_one "$name"
        status=$?
        set -e
        if [ "$status" -eq 0 ]; then
            next+=("$name")
        elif [ "$status" -eq 2 ]; then
            echo "recipe: skipping $name because when conditions do not match target"
        else
            return "$status"
        fi
    done
    RECIPE_PLAN=("${next[@]}")
}

recipe_validate_conflicts() {
    local name
    local conflict
    local file

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        while IFS= read -r conflict; do
            [ -n "$conflict" ] || continue
            if recipe_has_name "$conflict"; then
                recipe_die "$name conflicts with enabled recipe $conflict"
            fi
        done < <(recipe_json_lines "$file" '.conflicts[]?')
    done
}

recipe_validate_paths() {
    local seen_targets=""
    local seen_configs=""
    local name
    local file
    local target
    local config

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        while IFS= read -r target; do
            [ -n "$target" ] || continue
            if printf '%b' "$seen_targets" | grep -Fxq "$target"; then
                recipe_die "multiple recipes write target path '$target'"
            fi
            seen_targets="${seen_targets}${target}\n"
        done < <(recipe_json_lines "$file" '.actions.files[]?.target, .actions.patches[]?.target')

        while IFS= read -r config; do
            [ -n "$config" ] || continue
            target="$(recipe_dir "$name")/$config"
            if printf '%b' "$seen_configs" | grep -Fxq "$target"; then
                recipe_die "duplicate config entry '$config' in recipe '$name'"
            fi
            seen_configs="${seen_configs}${target}\n"
        done < <(recipe_json_lines "$file" '.actions.configs[]?')
    done
}

recipe_array_contains() {
    local array_name="$1"
    local value="$2"
    local item
    eval '
        for item in "${'"$array_name"'[@]}"; do
            if [ "$item" = "$value" ]; then
                return 0
            fi
        done
    '
    return 1
}

recipe_is_safe_relative_path() {
    local path="$1"
    if [[ "$path" =~ ^/ ]] || [[ "$path" =~ ^[a-zA-Z]: ]]; then
        return 1
    fi
    if [[ "/$path/" =~ /\.\./ ]]; then
        return 1
    fi
    return 0
}

recipe_validate_action_paths() {
    local name
    local file
    local target
    local source
    local remove_dir
    local config

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        
        while IFS= read -r target; do
            [ -n "$target" ] || continue
            recipe_is_safe_relative_path "$target" || recipe_die "recipe '$name' has unsafe target path '$target'"
        done < <(recipe_json_lines "$file" '.actions.files[]?.target')
        
        while IFS= read -r source; do
            [ -n "$source" ] || continue
            recipe_is_safe_relative_path "$source" || recipe_die "recipe '$name' has unsafe source path '$source'"
        done < <(recipe_json_lines "$file" '.actions.files[]?.source')

        while IFS= read -r target; do
            [ -n "$target" ] || continue
            recipe_is_safe_relative_path "$target" || recipe_die "recipe '$name' has unsafe patch target path '$target'"
        done < <(recipe_json_lines "$file" '.actions.patches[]?.target')
        
        while IFS= read -r source; do
            [ -n "$source" ] || continue
            recipe_is_safe_relative_path "$source" || recipe_die "recipe '$name' has unsafe patch source path '$source'"
        done < <(recipe_json_lines "$file" '.actions.patches[]?.source')

        while IFS= read -r remove_dir; do
            [ -n "$remove_dir" ] || continue
            recipe_is_safe_relative_path "$remove_dir" || recipe_die "recipe '$name' has unsafe removePackageDirs path '$remove_dir'"
        done < <(recipe_json_lines "$file" '.actions.removePackageDirs[]?')

        while IFS= read -r target; do
            [ -n "$target" ] || continue
            recipe_is_safe_relative_path "$target" || recipe_die "recipe '$name' has unsafe importPackages target path '$target'"
        done < <(recipe_json_lines "$file" '.actions.importPackages[]?.target // empty')

        while IFS= read -r config; do
            [ -n "$config" ] || continue
            recipe_is_safe_relative_path "$config" || recipe_die "recipe '$name' has unsafe configs path '$config'"
        done < <(recipe_json_lines "$file" '.actions.configs[]?')
    done
}

recipe_validate_dependency_completeness() {
    local name
    local file
    local phase
    local rank
    local dep
    local dep_file
    local dep_phase
    local dep_rank

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        phase=$(recipe_json_get "$file" '.phase')
        rank=$(recipe_phase_rank "$phase")
        
        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            if ! recipe_has_name "$dep"; then
                recipe_die "recipe '$name' is in the build plan, but its dependency '$dep' is missing or was filtered out"
            fi
            
            # Allow dependencies to run in different phases, since phase sequence naturally governs the execution order.
            :
        done < <(recipe_json_lines "$file" '.depends[]?')
    done
}

recipe_sort_phase_kahn() {
    local phase="$1"
    shift
    local phase_recipes=("$@")
    [ ${#phase_recipes[@]} -eq 0 ] && return 0

    local sorted=()
    local ready=()
    
    local in_degree=()
    local priority=()
    
    local i name dep file
    for i in "${!phase_recipes[@]}"; do
        name="${phase_recipes[i]}"
        file=$(recipe_json_path "$name")
        priority[i]=$(recipe_json_get_optional "$file" '.priority // 0')
        in_degree[i]=0
        
        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            if recipe_array_contains "phase_recipes" "$dep"; then
                in_degree[i]=$((in_degree[i] + 1))
            fi
        done < <(recipe_json_lines "$file" '.depends[]?')
    done
    
    for i in "${!phase_recipes[@]}"; do
        if [ "${in_degree[i]}" -eq 0 ]; then
            ready+=("${phase_recipes[i]}")
        fi
    done
    
    while [ ${#ready[@]} -gt 0 ]; do
        local r_len=${#ready[@]}
        local r_i r_j temp
        for ((r_i=0; r_i<r_len; r_i++)); do
            for ((r_j=r_i+1; r_j<r_len; r_j++)); do
                local name_i="${ready[r_i]}"
                local name_j="${ready[r_j]}"
                
                local prio_i=0
                local idx
                for idx in "${!phase_recipes[@]}"; do
                    if [ "${phase_recipes[idx]}" = "$name_i" ]; then
                        prio_i="${priority[idx]}"
                        break
                    fi
                done
                
                local prio_j=0
                for idx in "${!phase_recipes[@]}"; do
                    if [ "${phase_recipes[idx]}" = "$name_j" ]; then
                        prio_j="${priority[idx]}"
                        break
                    fi
                done
                
                local swap=0
                if [ "$prio_j" -gt "$prio_i" ]; then
                    swap=1
                elif [ "$prio_j" -eq "$prio_i" ]; then
                    if [[ "$name_j" < "$name_i" ]]; then
                        swap=1
                    fi
                fi
                
                if [ "$swap" -eq 1 ]; then
                    temp="${ready[r_i]}"
                    ready[r_i]="${ready[r_j]}"
                    ready[r_j]="$temp"
                fi
            done
        done
        
        local u="${ready[0]}"
        ready=("${ready[@]:1}")
        sorted+=("$u")
        
        for i in "${!phase_recipes[@]}"; do
            name="${phase_recipes[i]}"
            file=$(recipe_json_path "$name")
            if recipe_json_lines "$file" '.depends[]?' | grep -Fxq "$u"; then
                in_degree[i]=$((in_degree[i] - 1))
                if [ "${in_degree[i]}" -eq 0 ]; then
                    ready+=("$name")
                fi
            fi
        done
    done
    
    if [ "${#sorted[@]}" -ne "${#phase_recipes[@]}" ]; then
        recipe_die "circular dependency detected in phase '$phase'"
    fi
    
    for name in "${sorted[@]}"; do
        printf '%s\n' "$name"
    done
}

recipe_sort_plan() {
    local sorted_plan=()
    local phase
    
    for phase in "${RECIPE_PHASES[@]}"; do
        local phase_recipes=()
        local name
        local file
        for name in "${RECIPE_PLAN[@]}"; do
            file=$(recipe_json_path "$name")
            if [ "$(recipe_json_get "$file" '.phase')" = "$phase" ]; then
                phase_recipes+=("$name")
            fi
        done
        
        if [ ${#phase_recipes[@]} -gt 0 ]; then
            while IFS= read -r name; do
                [ -n "$name" ] || continue
                sorted_plan+=("$name")
            done < <(recipe_sort_phase_kahn "$phase" "${phase_recipes[@]}")
        fi
    done
    
    RECIPE_PLAN=("${sorted_plan[@]}")
}

recipe_list_all_names() {
    local recipe_json
    local name
    local declared
    local names=""

    for recipe_json in "$RECIPE_BASE_PATH"/recipes/*/recipe.json; do
        [ -f "$recipe_json" ] || continue
        recipe_validate_structure "$recipe_json"
        name=$(basename "$(dirname "$recipe_json")")
        declared=$(recipe_json_get "$recipe_json" '.name')
        [ "$declared" = "$name" ] || recipe_die "$name: name must equal directory name"
        names="${names}${name}\n"
    done

    printf '%b' "$names" | LC_ALL=C sort
}

recipe_collect_csv_set() {
    local ini_path="$1"
    local key="$2"
    local raw

    raw=$(recipe_target_ini_get "$ini_path" "$key")
    recipe_split_csv "$raw"
}

recipe_is_default_enabled() {
    local name="$1"
    local file

    file=$(recipe_json_path "$name")
    [ "$(recipe_json_get "$file" '.enabled')" = "true" ]
}

recipe_compute_target_enabled() {
    local name="$1"
    local current

    while IFS= read -r current; do
        [ -n "$current" ] || continue
        if [ "$current" = "$name" ]; then
            return 1
        fi
    done < <(recipe_collect_csv_set "$RECIPE_TARGET_INI" DISABLE_RECIPES)

    while IFS= read -r current; do
        [ -n "$current" ] || continue
        if [ "$current" = "$name" ]; then
            return 0
        fi
    done < <(recipe_collect_csv_set "$RECIPE_TARGET_INI" RECIPES)

    recipe_is_default_enabled "$name"
}

recipe_required_by_enabled() {
    local wanted="$1"
    local name
    local file
    local dep

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            if [ "$dep" = "$wanted" ]; then
                printf '%s\n' "$name"
                break
            fi
        done < <(recipe_json_lines "$file" '.depends[]?')
    done
}


recipe_build_plan() {
    recipe_validate_global_registry
    recipe_scan_initial_plan
    recipe_resolve_depends
    recipe_filter_conditions
    recipe_resolve_depends
    recipe_filter_conditions
    recipe_validate_dependency_completeness
    recipe_validate_conflicts
    recipe_validate_action_paths
    recipe_validate_paths
    recipe_build_import_registry
    recipe_validate_import_package_sources
    recipe_sort_plan
}

recipe_build_import_registry() {
    local registry="$RECIPE_BASE_PATH/recipes/import_registry.json"
    local merged="$RECIPE_BUILD_DIR/.recipe_import_registry.json"
    local name
    local file

    cp "$registry" "$merged"

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        jq -e --arg recipe_name "$name" '
            . as $recipe
            | ($recipe.actions.importPackagesRegistry // {}) as $local
            | reduce ($local | keys_unsorted[]) as $key (
                input;
                if .sources[$key] == null then
                    .sources[$key] = $local[$key]
                elif .sources[$key] == $local[$key] then
                    .
                else
                    error("recipe \($recipe_name) redefines importPackagesRegistry source \($key) with different content")
                end
            )
        ' "$file" "$merged" > "$merged.tmp" || recipe_die "failed to merge importPackagesRegistry for recipe '$name'"
        mv "$merged.tmp" "$merged"
    done

    RECIPE_IMPORT_REGISTRY="$merged"
}

recipe_validate_import_package_sources() {
    local name
    local file
    local source_label

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        while IFS= read -r source_label; do
            [ -n "$source_label" ] || continue
            jq -e --arg source_key "$source_label" '.sources[$source_key] != null' "$RECIPE_IMPORT_REGISTRY" >/dev/null || recipe_die "recipe '$name' references unknown importPackages source '$source_label'"
        done < <(recipe_json_lines "$file" '.actions.importPackages[]?.source')
    done
}

recipe_init() {
    RECIPE_TARGET_NAME="$1"
    RECIPE_TARGET_INI="$2"
    RECIPE_BUILD_DIR="$3"
    RECIPE_REPO_URL="$4"
    RECIPE_REPO_BRANCH="$5"
    RECIPE_BASE_PATH="${6:-$BASE_PATH}"

    if ! command -v jq >/dev/null 2>&1; then
        echo "recipe: warning: jq is not installed. Skipping recipe system..." >&2
        RECIPE_PLAN=()
        return 0
    fi

    if [ -z "$RECIPE_TARGET_NAME" ] || [ -z "$RECIPE_TARGET_INI" ] || [ -z "$RECIPE_BUILD_DIR" ]; then
        recipe_die "recipe_init requires target name, target ini, and build dir"
    fi
    [ -f "$RECIPE_TARGET_INI" ] || recipe_die "target ini not found: $RECIPE_TARGET_INI"
    [ -d "$RECIPE_BASE_PATH/recipes" ] || recipe_die "recipes directory not found: $RECIPE_BASE_PATH/recipes"

    RECIPE_TARGET_TAGS=$(recipe_target_ini_get "$RECIPE_TARGET_INI" TARGET_TAGS)
    recipe_build_plan
}

recipe_print_plan() {
    local name
    local file
    local phase

    echo "Recipe plan for ${RECIPE_TARGET_NAME}:"
    if [ "${#RECIPE_PLAN[@]}" -eq 0 ]; then
        echo "  (empty)"
        return 0
    fi
    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        phase=$(recipe_json_get "$file" '.phase')
        printf '  - [%s] %s\n' "$phase" "$name"
    done
}

recipe_ensure_parent_dir() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
}

recipe_copy_mapping() {
    local name="$1"
    local source_rel="$2"
    local target_rel="$3"
    local mode="${4:-0644}"
    local source_path
    local target_path

    source_path="$(recipe_dir "$name")/$source_rel"
    target_path="$RECIPE_BUILD_DIR/$target_rel"

    [ -f "$source_path" ] || recipe_die "$name: source file not found: $source_rel"
    recipe_ensure_parent_dir "$target_path"
    install -Dm"$mode" "$source_path" "$target_path"
    echo "recipe: $name installed $target_rel"
}

recipe_apply_config() {
    local name="$1"
    local config_rel="$2"
    local source_path
    local target_config="$RECIPE_BUILD_DIR/.config"

    source_path="$(recipe_dir "$name")/$config_rel"
    [ -f "$source_path" ] || recipe_die "$name: config fragment not found: $config_rel"
    [ -f "$target_config" ] || recipe_die "$name: target .config not found for configs"
    printf '\n# recipe: %s (%s)\n' "$name" "$config_rel" >> "$target_config"
    cat "$source_path" >> "$target_config"
    printf '\n' >> "$target_config"
    echo "recipe: $name appended config $config_rel"
}

recipe_get_feeds_path() {
    if declare -F get_feeds_path >/dev/null 2>&1; then
        get_feeds_path
        return 0
    fi
    if [ -f "$RECIPE_BUILD_DIR/feeds.conf" ]; then
        printf '%s\n' "$RECIPE_BUILD_DIR/feeds.conf"
    else
        printf '%s\n' "$RECIPE_BUILD_DIR/feeds.conf.default"
    fi
}

recipe_apply_add_feed() {
    local entry="$1"
    local feeds_path
    local feed_name

    feeds_path=$(recipe_get_feeds_path)
    [ -f "$feeds_path" ] || recipe_die "feeds file not found: $feeds_path"
    feed_name=$(printf '%s\n' "$entry" | awk '{print $2}')
    [ -n "$feed_name" ] || recipe_die "malformed addFeeds entry '$entry'"

    local found=0
    while read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$(echo "$line" | xargs)" ]] && continue
        local name
        name=$(echo "$line" | awk '{print $2}')
        if [ "$name" = "$feed_name" ]; then
            found=1
            break
        fi
    done < "$feeds_path"

    if [ "$found" -eq 0 ]; then
        [ -z "$(tail -c 1 "$feeds_path")" ] || echo "" >> "$feeds_path"
        echo "$entry" >> "$feeds_path"
    fi
}

recipe_apply_remove_feed() {
    local feed_name="$1"
    local feeds_path

    feeds_path=$(recipe_get_feeds_path)
    [ -f "$feeds_path" ] || recipe_die "feeds file not found: $feeds_path"
    awk -v target="$feed_name" '
        {
            if ($0 !~ /^[[:space:]]*#/ && $2 == target) {
                next
            }
            print
        }
    ' "$feeds_path" > "${feeds_path}.tmp" && mv "${feeds_path}.tmp" "$feeds_path"
}

recipe_registry_get() {
    local source_key="$1"
    local expr="$2"

    jq -er --arg source_key "$source_key" ".sources[\$source_key] | $expr" "$RECIPE_IMPORT_REGISTRY"
}

recipe_registry_get_optional() {
    local source_key="$1"
    local expr="$2"

    jq -er --arg source_key "$source_key" ".sources[\$source_key] | $expr" "$RECIPE_IMPORT_REGISTRY" 2>/dev/null || true
}

recipe_apply_import_package() {
    local source_label="$1"
    local import_name="$2"
    local import_target="$3"
    local repo_url
    local repo_branch
    local sparse_root
    local source_dir
    local target_rel
    local target_dir

    [ -n "$source_label" ] || recipe_die "importPackages entry missing source"
    [ -n "$import_name" ] || recipe_die "importPackages entry missing name"

    repo_url=$(recipe_registry_get "$source_label" '.gitUrl') || recipe_die "IMPORT_PACKAGES registry missing entry: $source_label"
    repo_branch=$(recipe_registry_get_optional "$source_label" '.branch // empty')
    sparse_root=$(recipe_registry_get_optional "$source_label" '.sparseRoot // empty')

    if [ -n "$sparse_root" ]; then
        source_dir="$sparse_root/$import_name"
    else
        source_dir="$import_name"
    fi

    if [ -n "$import_target" ]; then
        target_rel="$import_target"
    else
        target_rel="package/$import_name"
    fi
    target_dir="$RECIPE_BUILD_DIR/$target_rel"
    mkdir -p "$(dirname "$target_dir")"

    if declare -F sync_sparse_packages_to_feed_dir >/dev/null 2>&1; then
        local tmp_target
        tmp_target=$(mktemp -d)
        if ! sync_sparse_packages_to_feed_dir "$repo_url" "$repo_branch" "$tmp_target" "$source_label" "$source_dir"; then
            rm -rf "$tmp_target"
            return 1
        fi
        [ -d "$tmp_target/$source_dir" ] || recipe_die "$source_label lacks sparse path $source_dir"
        rm -rf "$target_dir"
        mv "$tmp_target/$source_dir" "$target_dir"
        rm -rf "$tmp_target"
    else
        local tmp_dir
        local clone_args=(clone --depth 1 --filter=blob:none --sparse)
        tmp_dir=$(mktemp -d)
        if [ -n "$repo_branch" ]; then
            clone_args+=(-b "$repo_branch")
        fi
        clone_args+=("$repo_url" "$tmp_dir")
        git "${clone_args[@]}"
        git -C "$tmp_dir" sparse-checkout set "$source_dir"
        [ -d "$tmp_dir/$source_dir" ] || recipe_die "$source_label lacks sparse path $source_dir"
        rm -rf "$target_dir"
        mv "$tmp_dir/$source_dir" "$target_dir"
        rm -rf "$tmp_dir"
    fi
    echo "recipe: imported $source_label:$import_name to $target_rel"
}

recipe_run_script() {
    local name="$1"
    local script_rel="$2"
    local script_path

    script_path="$(recipe_dir "$name")/$script_rel"
    [ -f "$script_path" ] || recipe_die "$name: script not found: $script_rel"
    RECIPE_DIR="$(recipe_dir "$name")" \
    TARGET_NAME="$RECIPE_TARGET_NAME" \
    TARGET_INI="$RECIPE_TARGET_INI" \
    BUILD_DIR="$RECIPE_BUILD_DIR" \
    REPO_URL="$RECIPE_REPO_URL" \
    REPO_BRANCH="$RECIPE_REPO_BRANCH" \
    BASE_PATH="$RECIPE_BASE_PATH" \
        bash "$script_path"
}

recipe_apply_copy_actions() {
    local name="$1"
    local file="$2"
    local expr="$3"
    local entry
    local source_rel
    local target_rel
    local mode

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        source_rel=$(recipe_json_object_get "$entry" '.source')
        target_rel=$(recipe_json_object_get "$entry" '.target')
        mode=$(recipe_json_object_get_optional "$entry" '.mode // empty')
        recipe_copy_mapping "$name" "$source_rel" "$target_rel" "${mode:-0644}"
    done < <(recipe_json_lines "$file" "$expr")
}

recipe_apply_one() {
    local name="$1"
    local file
    local entry
    local source_label
    local import_name
    local import_target
    local script

    file=$(recipe_json_path "$name")

    while IFS= read -r entry; do [ -n "$entry" ] && recipe_apply_add_feed "$entry"; done < <(recipe_json_lines "$file" '.actions.addFeeds[]?')
    while IFS= read -r entry; do [ -n "$entry" ] && recipe_apply_remove_feed "$entry"; done < <(recipe_json_lines "$file" '.actions.removeFeeds[]?')
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        source_label=$(recipe_json_object_get "$entry" '.source')
        import_name=$(recipe_json_object_get "$entry" '.name')
        import_target=$(recipe_json_object_get_optional "$entry" '.target // empty')
        recipe_apply_import_package "$source_label" "$import_name" "$import_target"
    done < <(recipe_json_lines "$file" '.actions.importPackages[]? | @json')
    while IFS= read -r entry; do [ -n "$entry" ] && rm -rf "$RECIPE_BUILD_DIR/$entry"; done < <(recipe_json_lines "$file" '.actions.removePackageDirs[]?')

    recipe_apply_copy_actions "$name" "$file" '.actions.patches[]? | @json'
    recipe_apply_copy_actions "$name" "$file" '.actions.files[]? | @json'

    while IFS= read -r entry; do [ -n "$entry" ] && recipe_apply_config "$name" "$entry"; done < <(recipe_json_lines "$file" '.actions.configs[]?')

    script=$(recipe_json_get_optional "$file" '.actions.script // empty')
    if [ -n "$script" ]; then
        recipe_run_script "$name" "$script"
    fi
}

recipe_run_phase() {
    local phase="$1"
    local name
    local file

    [ "${#RECIPE_PLAN[@]}" -gt 0 ] || return 0
    recipe_phase_rank "$phase" >/dev/null || recipe_die "invalid requested phase '$phase'"

    for name in "${RECIPE_PLAN[@]}"; do
        file=$(recipe_json_path "$name")
        if [ "$(recipe_json_get "$file" '.phase')" = "$phase" ]; then
            recipe_log_boundary BEGIN "$phase" "$name"
            recipe_apply_one "$name"
            recipe_log_boundary END "$phase" "$name"
        fi
    done
}
