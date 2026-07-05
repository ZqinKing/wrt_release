#!/usr/bin/env bash

recipe_cli_colors_init() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        RECIPE_CLI_RESET=$'\033[0m'
        RECIPE_CLI_BOLD=$'\033[1m'
        RECIPE_CLI_DIM=$'\033[2m'
        RECIPE_CLI_RED=$'\033[31m'
        RECIPE_CLI_GREEN=$'\033[32m'
        RECIPE_CLI_YELLOW=$'\033[33m'
        RECIPE_CLI_BLUE=$'\033[34m'
        RECIPE_CLI_MAGENTA=$'\033[35m'
        RECIPE_CLI_CYAN=$'\033[36m'
    else
        RECIPE_CLI_RESET=''
        RECIPE_CLI_BOLD=''
        RECIPE_CLI_DIM=''
        RECIPE_CLI_RED=''
        RECIPE_CLI_GREEN=''
        RECIPE_CLI_YELLOW=''
        RECIPE_CLI_BLUE=''
        RECIPE_CLI_MAGENTA=''
        RECIPE_CLI_CYAN=''
    fi
}

recipe_cli_style() {
    local style="$1"
    local text="$2"

    printf '%s%s%s' "$style" "$text" "$RECIPE_CLI_RESET"
}

recipe_cli_pad_style() {
    local width="$1"
    local style="$2"
    local text="$3"
    local padded

    printf -v padded "%-${width}s" "$text"
    recipe_cli_style "$style" "$padded"
}

recipe_cli_default_state_text() {
    local name="$1"

    if recipe_is_default_enabled "$name"; then
        recipe_cli_style "$RECIPE_CLI_CYAN" 'default=on'
    else
        recipe_cli_style "$RECIPE_CLI_DIM" 'default=off'
    fi
}

recipe_cli_target_state_text() {
    local name="$1"

    if recipe_has_name "$name"; then
        recipe_cli_style "$RECIPE_CLI_GREEN" 'target=on'
    else
        recipe_cli_style "$RECIPE_CLI_DIM" 'target=off'
    fi
}

recipe_cli_source_label_text() {
    local label="$1"

    case "$label" in
        RECIPES)
            recipe_cli_style "$RECIPE_CLI_GREEN" "$label"
            ;;
        DISABLE_RECIPES)
            recipe_cli_style "$RECIPE_CLI_YELLOW" "$label"
            ;;
        dependency)
            recipe_cli_style "$RECIPE_CLI_BLUE" "$label"
            ;;
        *)
            recipe_cli_style "$RECIPE_CLI_DIM" "$label"
            ;;
    esac
}

recipe_cli_notes_text() {
    local conflicts="$1"

    if [ -z "$conflicts" ]; then
        printf '%s' ''
        return 0
    fi

    recipe_cli_style "$RECIPE_CLI_RED" "conflicts: $(recipe_join_names_display "$conflicts")"
}

recipe_sort_unique_lines() {
    local content="$1"

    if [ -z "$content" ]; then
        return 0
    fi

    printf '%s\n' "$content" | awk 'NF { print }' | LC_ALL=C sort -u
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
        printf '%s\n' "$content"
        return 0
    fi

    if [ -z "$content" ]; then
        printf '%s\n' "$name"
    else
        printf '%s\n%s\n' "$content" "$name"
    fi
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
    printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_BOLD" 'Commands:')"
    printf '  %s  %s\n' "$(recipe_cli_style "$RECIPE_CLI_CYAN" 't <index>')" 'Toggle recipe for current target'
    printf '  %s  %s\n' "$(recipe_cli_style "$RECIPE_CLI_CYAN" 'd <index>')" 'Toggle recipe default enabled'
    printf '  %s  %s\n' "$(recipe_cli_style "$RECIPE_CLI_CYAN" 'p')" 'Print resolved execution plan'
    printf '  %s  %s\n' "$(recipe_cli_style "$RECIPE_CLI_CYAN" 'h')" 'Show this help'
    printf '  %s  %s\n' "$(recipe_cli_style "$RECIPE_CLI_CYAN" 'q')" 'Quit'
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
    local default_state_raw
    local target_state_raw
    local source_label
    local source_label_raw
    local conflicts
    local notes

    echo
    printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_BOLD$RECIPE_CLI_MAGENTA" "Recipe editor for ${RECIPE_TARGET_NAME}:")"
    printf '%s %s %s %s %s %s %s\n' \
        "$(recipe_cli_pad_style 5 "$RECIPE_CLI_BOLD" 'Index')" \
        "$(recipe_cli_pad_style 20 "$RECIPE_CLI_BOLD" 'Phase')" \
        "$(recipe_cli_pad_style 28 "$RECIPE_CLI_BOLD" 'Recipe')" \
        "$(recipe_cli_pad_style 12 "$RECIPE_CLI_BOLD" 'Default')" \
        "$(recipe_cli_pad_style 11 "$RECIPE_CLI_BOLD" 'Target')" \
        "$(recipe_cli_pad_style 16 "$RECIPE_CLI_BOLD" 'Source')" \
        "$(recipe_cli_style "$RECIPE_CLI_BOLD" 'Notes')"

    while IFS='|' read -r phase name; do
        [ -n "$name" ] || continue
        if recipe_is_default_enabled "$name"; then
            default_state_raw='default=on'
            default_state=$(recipe_cli_pad_style 12 "$RECIPE_CLI_CYAN" "$default_state_raw")
        else
            default_state_raw='default=off'
            default_state=$(recipe_cli_pad_style 12 "$RECIPE_CLI_DIM" "$default_state_raw")
        fi
        if recipe_has_name "$name"; then
            target_state_raw='target=on'
            target_state=$(recipe_cli_pad_style 11 "$RECIPE_CLI_GREEN" "$target_state_raw")
        else
            target_state_raw='target=off'
            target_state=$(recipe_cli_pad_style 11 "$RECIPE_CLI_DIM" "$target_state_raw")
        fi

        source_label_raw=$(recipe_current_source_label "$name")
        case "$source_label_raw" in
            RECIPES)
                source_label=$(recipe_cli_pad_style 16 "$RECIPE_CLI_GREEN" "$source_label_raw")
                ;;
            DISABLE_RECIPES)
                source_label=$(recipe_cli_pad_style 16 "$RECIPE_CLI_YELLOW" "$source_label_raw")
                ;;
            dependency)
                source_label=$(recipe_cli_pad_style 16 "$RECIPE_CLI_BLUE" "$source_label_raw")
                ;;
            *)
                source_label=$(recipe_cli_pad_style 16 "$RECIPE_CLI_DIM" "$source_label_raw")
                ;;
        esac
        notes=''
        conflicts=$(recipe_enabled_conflicts_for "$name")
        notes=$(recipe_cli_notes_text "$conflicts")
        printf '%-5s %-20s %-28s %s %s %s %s\n' \
            "$index" \
            "$phase" \
            "$name" \
            "$default_state" \
            "$target_state" \
            "$source_label" \
            "$notes"
        index=$((index + 1))
    done < <(recipe_plan_cli_rows)

    echo
}

recipe_toggle_conflict_message() {
    local name="$1"
    local conflicts

    conflicts=$(recipe_enabled_conflicts_for "$name")
    if [ -z "$conflicts" ]; then
        return 1
    fi

    printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_RED" "Cannot enable $name: conflicts with $(recipe_join_names_display "$conflicts")")"
    return 0
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

    if [ "$new_target_enabled" -eq 1 ] && ! recipe_has_name "$name"; then
        if recipe_toggle_conflict_message "$name"; then
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
    local currently_enabled=0

    if recipe_is_default_enabled "$name"; then
        recipe_write_json_enabled "$name" false
    else
        if recipe_has_name "$name"; then
            currently_enabled=1
        fi
        if [ "$currently_enabled" -eq 0 ] && recipe_toggle_conflict_message "$name"; then
            return 2
        fi
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

    recipe_cli_colors_init
    recipe_render_plan_cli
    recipe_print_plan_cli_help

    while true; do
        printf '%s' "$(recipe_cli_style "$RECIPE_CLI_BOLD$RECIPE_CLI_CYAN" 'plan> ')"
        IFS= read -r line || break
        line=$(recipe_trim "$line")
        [ -n "$line" ] || continue

        if [[ "$line" =~ ^([td])([0-9]+)$ ]]; then
            command="${BASH_REMATCH[1]}"
            index="${BASH_REMATCH[2]}"
        else
            command=${line%%[[:space:]]*}
            if [ "$command" = "$line" ]; then
                index=''
            else
                index=$(recipe_trim "${line#${command}}")
            fi
        fi

        if [ -z "$command" ]; then
            index=''
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
                    printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_RED" 'Invalid selection. Please enter a valid recipe index.')"
                    continue
                fi
                name=$(recipe_plan_cli_name_by_index "$index") || {
                    printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_RED" 'Invalid selection. Please enter a valid recipe index.')"
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
                    set +e
                    recipe_toggle_default_enabled "$name"
                    status=$?
                    set -e
                    if [ "$status" -ne 0 ]; then
                        if [ "$status" -eq 2 ]; then
                            continue
                        fi
                        exit "$status"
                    fi
                fi
                recipe_render_plan_cli
                ;;
            *)
                printf '%s\n' "$(recipe_cli_style "$RECIPE_CLI_RED" 'Invalid command. Enter h for help.')"
                ;;
        esac
    done
}
