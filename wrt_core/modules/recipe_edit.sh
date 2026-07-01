#!/usr/bin/env bash

recipe_sort_unique_lines() {
    local content="$1"

    if [ -z "$content" ]; then
        return 0
    fi

    printf '%b' "$content" | awk 'NF { print }' | LC_ALL=C sort -u
}

recipe_write_json_enabled() {
    local name="$1"
    local enabled="$2"
    local file
    local dir
    local tmp

    file=$(recipe_json_path "$name")
    dir=$(dirname "$file")
    tmp=$(mktemp "$dir/recipe.json.tmp.XXXXXX") || recipe_die "failed to create temp file for $file"
    jq --argjson enabled "$enabled" '.enabled = $enabled' "$file" > "$tmp" || {
        rm -f "$tmp"
        recipe_die "failed to update enabled in $file"
    }
    mv "$tmp" "$file" || {
        rm -f "$tmp"
        recipe_die "failed to replace $file"
    }
}

recipe_write_target_override_sets() {
    local ini_path="$1"
    local recipes_csv="$2"
    local disable_csv="$3"
    local tmp

    tmp=$(mktemp "$(dirname "$ini_path")/$(basename "$ini_path").tmp.XXXXXX") || recipe_die "failed to create temp file for $ini_path"
    awk -v recipes="$recipes_csv" -v disabled="$disable_csv" '
        BEGIN {
            wrote_recipes = 0
            wrote_disabled = 0
        }
        /^RECIPES=/ {
            print "RECIPES=" recipes
            wrote_recipes = 1
            next
        }
        /^DISABLE_RECIPES=/ {
            print "DISABLE_RECIPES=" disabled
            wrote_disabled = 1
            next
        }
        { print }
        END {
            if (!wrote_recipes) {
                print "RECIPES=" recipes
            }
            if (!wrote_disabled) {
                print "DISABLE_RECIPES=" disabled
            }
        }
    ' "$ini_path" > "$tmp" || {
        rm -f "$tmp"
        recipe_die "failed to update $ini_path"
    }
    mv "$tmp" "$ini_path" || {
        rm -f "$tmp"
        recipe_die "failed to replace $ini_path"
    }
}

recipe_rebuild_plan() {
    recipe_build_plan
}

recipe_set_contains() {
    local content="$1"
    local wanted="$2"
    local item

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$item" = "$wanted" ]; then
            return 0
        fi
    done < <(printf '%s\n' "$content")

    return 1
}

recipe_set_add() {
    local content="$1"
    local name="$2"

    if recipe_set_contains "$content" "$name"; then
        printf '%b' "$content"
        return 0
    fi

    printf '%b%s\n' "$content" "$name"
}

recipe_set_remove() {
    local content="$1"
    local name="$2"
    local item

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$item" != "$name" ]; then
            printf '%s\n' "$item"
        fi
    done < <(printf '%s\n' "$content")
}

recipe_join_names_csv() {
    local content="$1"

    recipe_sort_unique_lines "$content" | paste -sd',' -
}

recipe_join_names_display() {
    local content="$1"
    local first=1
    local item

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$first" -eq 1 ]; then
            printf '%s' "$item"
            first=0
        else
            printf ', %s' "$item"
        fi
    done < <(printf '%s\n' "$content")
}

recipe_current_source_label() {
    local name="$1"
    local forced_recipes
    local forced_disabled
    local default_enabled=0

    forced_recipes=$(recipe_collect_csv_set "$RECIPE_TARGET_INI" RECIPES)
    if recipe_set_contains "$forced_recipes" "$name"; then
        printf '%s\n' 'RECIPES'
        return 0
    fi

    forced_disabled=$(recipe_collect_csv_set "$RECIPE_TARGET_INI" DISABLE_RECIPES)
    if recipe_set_contains "$forced_disabled" "$name"; then
        printf '%s\n' 'DISABLE_RECIPES'
        return 0
    fi

    if recipe_is_default_enabled "$name"; then
        default_enabled=1
    fi

    if [ "$default_enabled" -eq 0 ] && recipe_has_name "$name"; then
        printf '%s\n' 'dependency'
        return 0
    fi

    printf '%s\n' 'default'
}

recipe_print_plan_cli_help() {
    echo 'Commands:'
    echo '  t <index>  Toggle recipe for current target'
    echo '  d <index>  Toggle recipe default enabled'
    echo '  p          Print resolved execution plan'
    echo '  h          Show this help'
    echo '  q          Quit'
}

recipe_plan_cli_rows() {
    local names
    local name
    local file
    local phase
    local rank
    local sortable=""

    names=$(recipe_list_all_names)
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        file=$(recipe_json_path "$name")
        phase=$(recipe_json_get "$file" '.phase')
        rank=$(recipe_phase_rank "$phase")
        sortable="${sortable}${rank}|${phase}|${name}\n"
    done < <(printf '%s\n' "$names")

    printf '%b' "$sortable" | LC_ALL=C sort -t'|' -k1,1n -k2,2 -k3,3 | cut -d'|' -f2-
}

recipe_render_plan_cli() {
    local index=1
    local phase
    local name
    local default_state
    local target_state
    local source_label

    echo
    echo "Recipe editor for ${RECIPE_TARGET_NAME}:"
    printf '%-5s %-20s %-28s %-12s %-11s %s\n' 'Index' 'Phase' 'Recipe' 'Default' 'Target' 'Source'

    while IFS='|' read -r phase name; do
        [ -n "$name" ] || continue
        if recipe_is_default_enabled "$name"; then
            default_state='default=on'
        else
            default_state='default=off'
        fi
        if recipe_has_name "$name"; then
            target_state='target=on'
        else
            target_state='target=off'
        fi

        source_label=$(recipe_current_source_label "$name")
        printf '%-5s %-20s %-28s %-12s %-11s %s\n' "$index" "$phase" "$name" "$default_state" "$target_state" "$source_label"
        index=$((index + 1))
    done < <(recipe_plan_cli_rows)

    echo
}

recipe_plan_cli_name_by_index() {
    local wanted="$1"
    local index=1
    local phase
    local name

    while IFS='|' read -r phase name; do
        [ -n "$name" ] || continue
        if [ "$index" -eq "$wanted" ]; then
            printf '%s\n' "$name"
            return 0
        fi
        index=$((index + 1))
    done < <(recipe_plan_cli_rows)

    return 1
}

recipe_toggle_target_override() {
    local name="$1"
    local name_in_set
    local default_enabled=0
    local current_target_enabled=0
    local new_target_enabled=0
    local required_by=""
    local recipes_set=""
    local disabled_set=""
    local recipes_csv
    local disabled_csv

    if recipe_is_default_enabled "$name"; then
        default_enabled=1
    fi

    if recipe_compute_target_enabled "$name"; then
        current_target_enabled=1
    fi

    if [ "$current_target_enabled" -eq 1 ]; then
        new_target_enabled=0
    else
        new_target_enabled=1
    fi

    if [ "$new_target_enabled" -eq 0 ] && recipe_has_name "$name"; then
        required_by=$(recipe_required_by_enabled "$name")
        required_by=$(printf '%s\n' "$required_by" | awk -v name="$name" '$0 != name')
        if [ -n "$required_by" ]; then
            required_by=$(recipe_join_names_display "$required_by")
            echo "Cannot disable $name: required by $required_by"
            return 2
        fi
    fi

    while IFS= read -r name_in_set; do
        [ -n "$name_in_set" ] || continue
        recipes_set=$(recipe_set_add "$recipes_set" "$name_in_set")
    done < <(recipe_collect_csv_set "$RECIPE_TARGET_INI" RECIPES)

    while IFS= read -r name_in_set; do
        [ -n "$name_in_set" ] || continue
        disabled_set=$(recipe_set_add "$disabled_set" "$name_in_set")
    done < <(recipe_collect_csv_set "$RECIPE_TARGET_INI" DISABLE_RECIPES)

    recipes_set=$(recipe_set_remove "$recipes_set" "$name")
    disabled_set=$(recipe_set_remove "$disabled_set" "$name")

    if [ "$new_target_enabled" -eq "$default_enabled" ]; then
        :
    elif [ "$new_target_enabled" -eq 1 ]; then
        recipes_set=$(recipe_set_add "$recipes_set" "$name")
    else
        disabled_set=$(recipe_set_add "$disabled_set" "$name")
    fi

    recipes_csv=$(recipe_join_names_csv "$recipes_set")
    disabled_csv=$(recipe_join_names_csv "$disabled_set")
    recipe_write_target_override_sets "$RECIPE_TARGET_INI" "$recipes_csv" "$disabled_csv"
    recipe_rebuild_plan
}

recipe_toggle_default_enabled() {
    local name="$1"

    if recipe_is_default_enabled "$name"; then
        recipe_write_json_enabled "$name" false
    else
        recipe_write_json_enabled "$name" true
    fi
    recipe_rebuild_plan
}

recipe_open_config_cli() {
    local line
    local command
    local index
    local name
    local status

    recipe_render_plan_cli
    recipe_print_plan_cli_help

    while true; do
        printf 'plan> '
        IFS= read -r line || break
        line=$(recipe_trim "$line")
        [ -n "$line" ] || continue

        command=${line%%[[:space:]]*}
        if [ "$command" = "$line" ]; then
            index=''
        else
            index=$(recipe_trim "${line#${command}}")
        fi

        case "$command" in
            q)
                break
                ;;
            h)
                recipe_print_plan_cli_help
                ;;
            p)
                recipe_print_plan
                ;;
            t|d)
                if [[ ! "$index" =~ ^[0-9]+$ ]]; then
                    echo "Invalid selection. Please enter a valid recipe index."
                    continue
                fi
                name=$(recipe_plan_cli_name_by_index "$index") || {
                    echo "Invalid selection. Please enter a valid recipe index."
                    continue
                }
                if [ "$command" = 't' ]; then
                    set +e
                    recipe_toggle_target_override "$name"
                    status=$?
                    set -e
                    if [ "$status" -ne 0 ]; then
                        if [ "$status" -eq 2 ]; then
                            continue
                        fi
                        exit "$status"
                    fi
                else
                    recipe_toggle_default_enabled "$name"
                fi
                recipe_render_plan_cli
                ;;
            *)
                echo "Invalid command. Enter h for help."
                ;;
        esac
    done
}
