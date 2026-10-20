#!/usr/bin/env bash
# Self-check for the upload step's path handling. Runs the real script from
# action.yml against a stubbed `aws`, so it needs no credentials and no network.
#
#   ./actions/upload-s3/test.sh
#
# Exists because the path logic is where this action can silently do the wrong
# thing: an early version nested a directory under its own name
# (.../<name>/<name>/...), which no YAML linter would have caught.
set -uo pipefail

command -v python3 >/dev/null || { echo "SKIP: python3 required"; exit 0; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/aws" <<'STUB'
#!/bin/bash
[ "$1" = "--version" ] && { echo "aws-cli/1.0 (stub)"; exit 0; }
# A local stand-in for the bucket: s3://<bucket>/<key> lives at $STORE/<bucket>/<key>.
if [ "$2" = "ls" ]; then
  p="${3#s3://}"; p="${p%/}"
  [ -d "$STORE/$p" ] || exit 0
  (cd "$STORE" && find "$p" -type f) | while IFS= read -r k; do
    printf '2026-01-01 00:00:00 %10s %s\n' "$(wc -c < "$STORE/$k" | tr -d ' ')" "${k#*/}"
  done
  exit 0
fi
if [ "$1" = "s3api" ]; then # list-objects-v2 --bucket B --prefix P/ ...: print the object count
  [ -n "${STUB_DENY:-}" ] && { echo "AccessDenied" >&2; exit 254; }
  d="$STORE/$4/$6"; [ -d "$d" ] && find "$d" -type f | wc -l | tr -d ' ' || echo 0
  exit 0
fi
echo "$*" >> "$CALLS"
# aws-cli 2.36 after a no-response timeout: exit 0, nothing stored.
[ -n "${STUB_DROP:-}" ] && exit 0
dst="$STORE/${4#s3://}"
if [ "$5" = "--recursive" ]; then mkdir -p "$dst" && cp -RL "$3"/. "$dst"/
else mkdir -p "$(dirname "$dst")" && cp -L "$3" "$dst"; fi
STUB
chmod +x "$TMP/bin/aws"

python3 -c "
import yaml,sys
print(yaml.safe_load(open('$HERE/action.yml'))['runs']['steps'][1]['run'])
" > "$TMP/upload.sh" || { echo "FAIL: could not extract script (pyyaml missing?)"; exit 1; }

mkdir -p "$TMP/work/reports" "$TMP/work/d1" "$TMP/work/d2"
cd "$TMP/work"
echo a > reports/r1.txt; echo b > single.log; echo c > x1.diff; echo d > x2.diff
echo e > d1/a; echo f > d2/b

fails=0
run() { # run <name> <path> [if-no-files-found]; KEEP=1 keeps the bucket from the last run
  export CALLS="$TMP/calls.log"; : > "$CALLS"
  export STORE="$TMP/store"; [ -n "${KEEP:-}" ] || rm -rf "$STORE"
  : > "$TMP/out"
  PATH="$TMP/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_OUTPUT="$TMP/out" \
  GITHUB_RUN_ATTEMPT="${ATTEMPT-1}" PER_ATTEMPT="${PER:-false}" \
  AWS_ACCESS_KEY_ID=k AWS_SECRET_ACCESS_KEY=s BUCKET=b ENDPOINT=https://e RUNNER_TEMP="$TMP" \
  IN_NAME="$1" IN_PATH="$2" ON_MISSING="${3:-warn}" bash "$TMP/upload.sh" >/dev/null 2>&1
  RC=$?
}
ok() { if [ "$1" = "$2" ]; then echo "  ok: $3"; else echo "  FAIL: $3 (got '$1' want '$2')"; fails=$((fails+1)); fi; }

run art single.log
ok "$(grep -c 's3://b/o/r/1/art/single.log' "$TMP/calls.log")" 1 "file keeps its basename"
ok "$RC" 0 "uploaded file verifies"

mkdir -p reports/sub; echo nested > reports/sub/r2.txt; : > reports/empty.txt
ln -s r1.txt reports/link.txt
run art reports
ok "$(grep -c 's3://b/o/r/1/art/ --recursive' "$TMP/calls.log")" 1 "lone directory is not nested under its own name"
ok "$RC" 0 "uploaded directory verifies (nested, empty, symlinked files)"
run art reports/
ok "$RC" 0 "trailing slash on a directory verifies"

run art 'd?'
ok "$(grep -c 's3://b/o/r/1/art/d1/' "$TMP/calls.log")" 1 "multiple dirs disambiguated by basename"
ok "$RC" 0 "multiple dirs verify"

run art '*.diff'
ok "$(wc -l < "$TMP/calls.log")" 2 "glob uploads every match"

mkdir -p deep/a/b; echo x > deep/a/one.log; echo y > deep/a/b/two.log
run art 'deep/**/*.log'
ok "$(wc -l < "$TMP/calls.log")" 2 "** recurses more than one level (needs globstar)"

mkdir -p dup/a dup/b; echo short > dup/a/p.log; echo much-longer > dup/b/p.log
run art 'dup/**/p.log'
ok "$RC" 0 "same-basename matches keep the old last-one-wins result instead of failing"

STUB_DROP=1 run art reports
ok "$RC" 1 "aws exiting 0 without storing anything fails the step"
STUB_DROP=1 run art single.log
ok "$RC" 1 "a dropped single file fails the step"

ok "$(python3 -c "
import yaml
print(yaml.safe_load(open('$HERE/action.yml'))['runs']['steps'][1]['env'].get('AWS_EC2_METADATA_DISABLED'))
")" true "IMDS lookups are off (aws-cli v2 spends ~6 s on them per call)"

# Re-runs. GitHub keeps GITHUB_RUN_ID and bumps GITHUB_RUN_ATTEMPT.
echo attempt1 > evidence.txt
run art evidence.txt
ok "$(cat "$TMP/out")" "s3-uri=s3://b/o/r/1/art" "default keeps the legacy key old consumers download from"
echo attempt-two > evidence.txt
KEEP=1 ATTEMPT=2 run art evidence.txt
ok "$RC/$(cat "$TMP/store/b/o/r/1/art/evidence.txt")" 0/attempt-two "default re-run still overwrites in place, as before"

echo attempt1 > evidence.txt
PER=true run art evidence.txt
ok "$RC/$(cat "$TMP/out")" "0/s3-uri=s3://b/o/r/1/attempt-1/art" "per-attempt keys attempt 1 and reports it in s3-uri"
echo attempt-two > evidence.txt
KEEP=1 PER=true ATTEMPT=2 run art evidence.txt
ok "$RC/$(cat "$TMP/out")" "0/s3-uri=s3://b/o/r/1/attempt-2/art" "per-attempt attempt 2 of the same run gets its own prefix"
ok "$(cat "$TMP/store/b/o/r/1/attempt-1/art/evidence.txt")/$(cat "$TMP/store/b/o/r/1/attempt-2/art/evidence.txt")" \
  attempt1/attempt-two "both attempts' evidence survives, distinguishable"
KEEP=1 PER=true ATTEMPT=2 run art evidence.txt
ok "$RC/$(wc -l < "$TMP/calls.log")" 1/0 "per-attempt refuses a second upload into the same attempt's prefix"
KEEP=1 PER=true ATTEMPT=2 run other evidence.txt
ok "$RC" 0 "a different name in the same attempt is fine"
KEEP=1 PER=true ATTEMPT=3 run art reports
ok "$RC/$(find "$TMP/store/b/o/r/1/attempt-3/art" -type f | wc -l | tr -d ' ')" 0/4 "per-attempt directory keeps its whole tree"
STUB_DROP=1 PER=true run art reports
ok "$RC" 1 "per-attempt still fails when aws stores nothing"
STUB_DENY=1 PER=true run art evidence.txt
ok "$RC/$(wc -l < "$TMP/calls.log")" 1/0 "per-attempt fails, uploading nothing, if it cannot check the prefix"
PER=true ATTEMPT= run art evidence.txt;   ok "$RC" 1 "per-attempt without GITHUB_RUN_ATTEMPT fails"
PER=yes run art evidence.txt;             ok "$RC" 1 "per-attempt rejects values other than true/false"

run art 'no-such-*' error;  ok "$RC" 1 "if-no-files-found=error fails the step"
run art 'no-such-*' ignore; ok "$RC" 0 "if-no-files-found=ignore passes"
run art 'no-such-*' warn;   ok "$RC" 0 "if-no-files-found=warn passes"

run art no-such-dir warn
ok "$RC/$(wc -l < "$TMP/calls.log")" 0/0 "missing plain path warns instead of handing aws a bad path"
run art no-such-dir error;  ok "$RC" 1 "missing plain path honours if-no-files-found=error"

export CALLS="$TMP/calls.log"; : > "$CALLS"
PATH="$TMP/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_OUTPUT="$TMP/out" \
AWS_ACCESS_KEY_ID="" AWS_SECRET_ACCESS_KEY=s BUCKET=b ENDPOINT=https://e \
IN_NAME=art IN_PATH=single.log ON_MISSING=warn bash "$TMP/upload.sh" >/dev/null 2>&1
ok "$?" 1 "empty credentials fail loudly instead of uploading nothing"

[ "$fails" -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed"
exit "$fails"
