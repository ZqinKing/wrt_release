#!/usr/bin/env bash
set -euo pipefail

base_files_path="$BUILD_DIR/package/base-files/files"
passwd_path="$base_files_path/etc/passwd"
ohmyzsh_dir="$base_files_path/root/.oh-my-zsh"
plugins_dir="$ohmyzsh_dir/custom/plugins"

git_clone_clean() {
    local url="$1"
    local target="$2"
    local max_retries=3
    local retry_count=0
    local success=0

    while [ "$retry_count" -lt "$max_retries" ]; do
        rm -rf "$target"
        echo "ohmyzsh: Cloning $url to $target (Attempt $((retry_count + 1))/$max_retries)..."
        if git clone --depth 1 "$url" "$target"; then
            success=1
            break
        fi
        retry_count=$((retry_count + 1))
        echo "ohmyzsh: Clone failed. Waiting 5 seconds before retrying..."
        sleep 5
    done

    if [ "$success" -ne 1 ]; then
        echo "ohmyzsh: Error: Failed to clone $url after $max_retries attempts." >&2
        return 1
    fi
}

mkdir -p "$base_files_path/root" "$base_files_path/etc"

if [ -f "$passwd_path" ]; then
    if grep -qx 'root:x:0:0:root:/root:/bin/ash' "$passwd_path"; then
        sed -i 's#^root:x:0:0:root:/root:/bin/ash$#root:x:0:0:root:/root:/bin/zsh#' "$passwd_path"
        echo "ohmyzsh: changed root shell from /bin/ash to /bin/zsh"
    elif grep -qx 'root:x:0:0:root:/root:/bin/zsh' "$passwd_path"; then
        echo "ohmyzsh: root shell already set to /bin/zsh"
    else
        echo "ohmyzsh: Warning: unexpected root entry in $passwd_path, skipping shell change" >&2
    fi
else
    echo "ohmyzsh: Warning: $passwd_path not found, skipping shell change" >&2
fi

git_clone_clean "https://github.com/ohmyzsh/ohmyzsh.git" "$ohmyzsh_dir"
mkdir -p "$plugins_dir"
git_clone_clean "https://github.com/marlonrichert/zsh-autocomplete.git" "$plugins_dir/zsh-autocomplete"
git_clone_clean "https://github.com/zsh-users/zsh-autosuggestions.git" "$plugins_dir/zsh-autosuggestions"
git_clone_clean "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$plugins_dir/zsh-syntax-highlighting"

# Remove all .git directories to save space in the firmware package
find "$ohmyzsh_dir" -name ".git" -exec rm -rf {} +

install -Dm0644 "$RECIPE_DIR/files/root/.zshrc" "$base_files_path/root/.zshrc"

echo "ohmyzsh: installed oh-my-zsh and zsh plugins"
