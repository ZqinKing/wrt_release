#!/usr/bin/env bash
# 外部 feed 软件包同步辅助。

sync_sparse_packages_to_feed_dir() {
    local repo_url="$1"
    local repo_branch="$2"
    local target_dir="$3"
    local repo_label="$4"
    shift 4

    local packages=("$@")
    local tmp_dir
    local missing_packages=()
    local clone_args=(clone --depth 1 --filter=blob:none --sparse)
    local pkg
    local target_pkg

    tmp_dir=$(mktemp -d) || return 1

    if [ -n "$repo_branch" ]; then
        clone_args+=(-b "$repo_branch")
    fi

    clone_args+=("$repo_url" "$tmp_dir")

    echo "正在从 $repo_label 稀疏同步指定目录..."
    if ! git_retry "${clone_args[@]}"; then
        echo "错误：从 $repo_url 拉取仓库骨架失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! git_retry -C "$tmp_dir" sparse-checkout set "${packages[@]}"; then
        echo "错误：配置 $repo_label 稀疏检出目录失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    for pkg in "${packages[@]}"; do
        if [ -d "$tmp_dir/$pkg" ]; then
            target_pkg="$target_dir/$pkg"
            if ! mkdir -p "$(dirname "$target_pkg")" || ! rm -rf "$target_pkg" || ! mv "$tmp_dir/$pkg" "$target_pkg"; then
                echo "错误：无法将 $repo_label 的 $pkg 移动到 $target_pkg" >&2
                rm -rf "$tmp_dir"
                return 1
            fi
        else
            missing_packages+=("$pkg")
        fi
    done

    rm -rf "$tmp_dir"

    if [ ${#missing_packages[@]} -ne 0 ]; then
        printf '错误：%s 仓库缺少以下必要目录：\n' "$repo_label" >&2
        printf '  - %s\n' "${missing_packages[@]}" >&2
        return 1
    fi
}

sync_repo_root_package_to_feed_dir() {
    local repo_url="$1"
    local repo_branch="$2"
    local target_dir="$3"
    local repo_label="$4"
    local package_name="$5"
    local keep_git="${6:-0}"
    local tmp_dir
    local clone_args=(clone --depth 1)
    if [[ "$keep_git" != "1" ]]; then
        clone_args+=(--filter=blob:none)
    fi

    tmp_dir=$(mktemp -d) || return 1

    if [ -n "$repo_branch" ]; then
        clone_args+=(-b "$repo_branch")
    fi

    clone_args+=("$repo_url" "$tmp_dir")

    echo "正在从 $repo_label 同步单包仓库..."
    if ! git_retry "${clone_args[@]}"; then
        echo "错误：从 $repo_url 克隆 $repo_label 失败" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    if [ ! -f "$tmp_dir/Makefile" ]; then
        echo "错误：$repo_label 仓库根目录缺少 OpenWrt 软件包 Makefile" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    if [[ "$keep_git" != "1" ]]; then
        rm -rf "$tmp_dir/.git"
    fi
    rm -rf "$target_dir/$package_name"

    if ! mv "$tmp_dir" "$target_dir/$package_name"; then
        echo "错误：无法将 $repo_label 移动到 $target_dir/$package_name" >&2
        rm -rf "$tmp_dir"
        return 1
    fi
}
