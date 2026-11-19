#!/usr/bin/env bash
set -euo pipefail

source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_CODENAME:-} != noble || $(dpkg --print-architecture) != amd64 ]]; then
    echo "CI build setup requires Ubuntu 24.04 (amd64)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null || ! dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -q 'install ok installed'; then
    apt-get update -y
    apt-get install -y ca-certificates curl
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Prefer the mirror that performed well in CI. APT tries other Ubuntu mirrors
# only when its normal downloads fail; no separate speed probes are needed.
printf '%s\tpriority:%s\n' \
    https://azure.archive.ubuntu.com/ubuntu/ 1 \
    https://archive.ubuntu.com/ubuntu/ 2 \
    https://security.ubuntu.com/ubuntu/ 3 \
    http://us-east-2.ec2.archive.ubuntu.com/ubuntu/ 4 \
    > /etc/apt/wrt-ubuntu-mirrors.txt
printf 'Ubuntu archive mirrors in download order:\n'
cat /etc/apt/wrt-ubuntu-mirrors.txt

# Only change Ubuntu archive URIs. Keep the runner's suites, signing key and
# other source settings, including any unrelated repositories.
sed -i -E '/^URIs:/ s#https?://(azure\.archive|us-east-2\.ec2\.archive|archive|security)\.ubuntu\.com/ubuntu/?([[:space:]]|$)|mirror\+file:/etc/apt/apt-mirrors\.txt([[:space:]]|$)#mirror+file:/etc/apt/wrt-ubuntu-mirrors.txt\2\3#g' \
    /etc/apt/sources.list.d/ubuntu.sources
grep -q '^URIs:.*mirror+file:/etc/apt/wrt-ubuntu-mirrors.txt' /etc/apt/sources.list.d/ubuntu.sources

printf 'Acquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::Retries "2";\n' \
    > /etc/apt/apt.conf.d/99-wrt-ci

curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
    https://build-scripts.immortalwrt.org/init_build_environment.sh \
    -o "$tmp/init.sh"

# Keep the current upstream dependency and tool setup, but avoid upgrading
# unrelated runner packages and triggering runner-wide post-install scripts.
sed -i -E '/^[[:blank:]]*apt full-upgrade -y /d' "$tmp/init.sh"

TMPDIR="$tmp" bash -e "$tmp/init.sh"
apt-get install -y dos2unix libfuse-dev
for tool in gcc g++ clang go node yarn gh ccache upx padjffs2 po2lmo; do
    command -v "$tool" >/dev/null || { echo "Missing WRT build tool: $tool" >&2; exit 1; }
done
apt-get clean
