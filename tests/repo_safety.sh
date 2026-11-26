#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/wrt_core/modules/lib/network.sh"
source "$ROOT/wrt_core/modules/repo.sh"
export NETWORK_RETRY_MAX=1 NETWORK_RETRY_DELAY=0
BASE_PATH="$ROOT/wrt_core"

reject_repo() {
    if validate_build_repo >"$WORK/rejected.log" 2>&1; then
        echo "FAIL: invalid build repository accepted: $BUILD_DIR" >&2
        exit 1
    fi
}

git init -q "$WORK/origin"
git -C "$WORK/origin" -c user.name=QA -c user.email=qa@example.invalid commit -q --allow-empty -m initial
REPO_BRANCH=$(git -C "$WORK/origin" branch --show-current)
REPO_URL="$WORK/origin"
BUILD_DIR="$WORK/build with spaces"
COMMIT_HASH=none
clone_repo >"$WORK/clone.log" 2>&1
validate_build_repo
git -C "$BUILD_DIR" config pull.rebase false
touch "$BUILD_DIR/disposable"
reset_feeds_conf >"$WORK/reset.log" 2>&1
[[ ! -e "$BUILD_DIR/disposable" ]]
echo "PASS: initial clone and reset target the isolated build repository"

git -C "$BUILD_DIR" remote set-url origin "$REPO_URL.git/"
validate_build_repo
echo "PASS: optional .git suffix and trailing slash compare equally"

git -C "$BUILD_DIR" remote set-url origin "$WORK/other-origin"
touch "$BUILD_DIR/keep"
reject_repo
[[ -f "$BUILD_DIR/keep" ]]
echo "PASS: mismatched source is rejected without cleaning files"

BUILD_DIR="$ROOT"
REPO_URL=$(git -C "$ROOT" remote get-url origin)
reject_repo
BUILD_DIR="$ROOT/wrt_core"
reject_repo
echo "PASS: orchestrator root and inherited parent repository are rejected"

git init -q "$WORK/project"
git -C "$WORK/project" remote add origin "$WORK/origin"
mkdir "$WORK/project/wrt_core"
BASE_PATH="$WORK/project/wrt_core"
BUILD_DIR="$WORK"
reject_repo
echo "PASS: a non-repository parent directory is rejected"
git init -q "$WORK"
git -C "$WORK" remote add origin "$REPO_URL"
reject_repo
echo "PASS: an ancestor repository is rejected even with a matching origin"
