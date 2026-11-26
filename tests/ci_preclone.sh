#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "CI fixture: $WORK"
PROJECT="$WORK/project"
mkdir -p "$PROJECT/wrt_core/ci" "$PROJECT/wrt_core/modules/lib" "$PROJECT/wrt_core/compilecfg"
cp -p "$ROOT/wrt_core/ci/pre_clone_action.sh" "$PROJECT/wrt_core/ci/"
cp "$ROOT/wrt_core/modules/lib/"{common,network}.sh "$PROJECT/wrt_core/modules/lib/"
git init -q -b main "$WORK/origin"
mkdir -p "$WORK/origin/scripts"
printf 'https://example.cn/file\nhttps://mirror.tencent.com/file\nhttps://official.invalid/file\n' >"$WORK/origin/scripts/projectsmirrors.json"
git -C "$WORK/origin" add scripts
git -C "$WORK/origin" -c user.name=QA -c user.email=qa@example.invalid commit -qm initial
HASH=$(git -C "$WORK/origin" rev-parse HEAD)
printf 'REPO_URL=%s\nREPO_BRANCH=main\nCOMMIT_HASH=%s\n' "$WORK/origin" "$HASH" >"$PROJECT/wrt_core/compilecfg/fixture.ini"
(cd "$PROJECT/wrt_core" && ./ci/pre_clone_action.sh fixture) >"$WORK/preclone.log" 2>&1
[[ $(<"$PROJECT/repo_flag") == "$WORK/origin/main/$HASH" ]]
git -C "$PROJECT/action_build" rev-parse --is-inside-work-tree
grep -qx 'https://official.invalid/file' "$PROJECT/action_build/scripts/projectsmirrors.json"
[[ $(wc -l <"$PROJECT/action_build/scripts/projectsmirrors.json") == 1 ]]
echo "PASS: direct CI entrypoint writes root cache flag and filters mirrors"

chmod -x "$PROJECT/wrt_core/ci/pre_clone_action.sh"
set +e
(cd "$PROJECT" && ./wrt_core/ci/pre_clone_action.sh fixture) >"$WORK/mode.log" 2>&1
status=$?
set -e
[[ $status == 126 ]]
echo "PASS: missing execute permission mutation fails with exit 126"
