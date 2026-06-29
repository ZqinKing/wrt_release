#!/usr/bin/env bash
set -euo pipefail

base_files_path="$BUILD_DIR/package/base-files/files"
ohmyzsh_dir="$base_files_path/root/.oh-my-zsh"
plugins_dir="$ohmyzsh_dir/custom/plugins"

git_clone_clean() {
    local url="$1"
    local target="$2"
    rm -rf "$target"
    git clone --depth 1 "$url" "$target"
}

mkdir -p "$base_files_path/root"

git_clone_clean "https://github.com/ohmyzsh/ohmyzsh.git" "$ohmyzsh_dir"
mkdir -p "$plugins_dir"
git_clone_clean "https://github.com/marlonrichert/zsh-autocomplete.git" "$plugins_dir/zsh-autocomplete"
git_clone_clean "https://github.com/zsh-users/zsh-autosuggestions.git" "$plugins_dir/zsh-autosuggestions"
git_clone_clean "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$plugins_dir/zsh-syntax-highlighting"

install -Dm0644 "$RECIPE_DIR/files/root/.zshrc" "$base_files_path/root/.zshrc"

echo "ohmyzsh: installed oh-my-zsh and zsh plugins"
