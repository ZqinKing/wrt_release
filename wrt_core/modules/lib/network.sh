#!/usr/bin/env bash

network_retry() {
    local max_attempts="${NETWORK_RETRY_MAX:-5}"
    local delay_seconds="${NETWORK_RETRY_DELAY:-5}"
    local attempt=1
    local exit_code

    while true; do
        "$@" && return 0
        exit_code=$?
        if ((attempt >= max_attempts)); then
            return "$exit_code"
        fi

        echo "网络命令失败，${delay_seconds}s 后重试 ($attempt/$max_attempts): $*" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

git_retry() {
    local max_attempts="${NETWORK_RETRY_MAX:-5}"
    local delay_seconds="${NETWORK_RETRY_DELAY:-5}"
    local attempt=1
    local exit_code
    local clone_target=""

    if [[ ${1:-} == "clone" ]]; then
        clone_target="${@: -1}"
    fi

    while true; do
        git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@" && return 0
        exit_code=$?
        if ((attempt >= max_attempts)); then
            return "$exit_code"
        fi

        if [[ -n "$clone_target" && -e "$clone_target" ]]; then
            rm -rf "$clone_target"
        fi

        echo "Git 网络操作失败，${delay_seconds}s 后重试 ($attempt/$max_attempts): git $*" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

curl_retry() {
    network_retry curl --retry 3 --retry-delay 2 --retry-all-errors "$@"
}

wget_retry() {
    network_retry wget --tries=3 --waitretry=2 "$@"
}
