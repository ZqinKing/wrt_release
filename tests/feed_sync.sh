#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "Feed sync fixture: $WORK"
source "${FEED_SYNC_MODULE:-$ROOT/wrt_core/modules/lib/feed_sync.sh}"
git_retry() { git "$@"; }
mkdir -p "$WORK/packages"
git init -q -b main "$WORK/origin"
cp "$ROOT/tests/fixtures/homeproxy.Makefile" "$WORK/origin/Makefile"
git -C "$WORK/origin" add Makefile
git -C "$WORK/origin" -c user.name=QA -c user.email=qa@example.invalid commit -qm snapshot
URL="file://$WORK/origin"

sync_repo_root_package_to_feed_dir "$URL" "" "$WORK/packages" HomeProxy plain
cmp "$ROOT/tests/fixtures/homeproxy.Makefile" "$WORK/packages/plain/Makefile"
[[ ! -e "$WORK/packages/plain/.git" ]]
echo "PASS: default root-package synchronization still strips Git metadata"

sync_repo_root_package_to_feed_dir "$URL" "" "$WORK/packages" HomeProxy kept 1
cmp "$ROOT/tests/fixtures/homeproxy.Makefile" "$WORK/packages/kept/Makefile"
git -C "$WORK/packages/kept" log -1 --format=%ct | grep -Eq '^[0-9]+$'
[[ $(git -C "$WORK/packages/kept" rev-parse --is-shallow-repository) == true ]]
[[ -z $(git -C "$WORK/packages/kept" config --get remote.origin.partialclonefilter || true) ]]
echo "PASS: keep_git preserves shallow history without partial-clone filtering"

git init -q -b main "$WORK/invalid"
git -C "$WORK/invalid" -c user.name=QA -c user.email=qa@example.invalid commit -q --allow-empty -m invalid
if sync_repo_root_package_to_feed_dir "file://$WORK/invalid" main "$WORK/packages" invalid kept 1; then
    echo "FAIL: root repository without a Makefile accepted" >&2
    exit 1
fi
cmp "$ROOT/tests/fixtures/homeproxy.Makefile" "$WORK/packages/kept/Makefile"
echo "PASS: invalid package leaves an existing valid destination intact"

if sync_sparse_packages_to_feed_dir "$URL" main "$WORK/packages" missing absent; then
    echo "FAIL: absent sparse package accepted" >&2
    exit 1
fi
[[ ! -e "$WORK/packages/absent" ]]
echo "PASS: missing sparse package fails"
