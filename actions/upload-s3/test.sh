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
echo "$*" >> "$CALLS"
exit 0
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
run() { # run <name> <path> [if-no-files-found]
  export CALLS="$TMP/calls.log"; : > "$CALLS"
  PATH="$TMP/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_OUTPUT="$TMP/out" \
  AWS_ACCESS_KEY_ID=k AWS_SECRET_ACCESS_KEY=s BUCKET=b ENDPOINT=https://e \
  IN_NAME="$1" IN_PATH="$2" ON_MISSING="${3:-warn}" bash "$TMP/upload.sh" >/dev/null 2>&1
  RC=$?
}
ok() { if [ "$1" = "$2" ]; then echo "  ok: $3"; else echo "  FAIL: $3 (got '$1' want '$2')"; fails=$((fails+1)); fi; }

run art single.log
ok "$(grep -c 's3://b/o/r/1/art/single.log' "$TMP/calls.log")" 1 "file keeps its basename"

run art reports
ok "$(grep -c 's3://b/o/r/1/art/ --recursive' "$TMP/calls.log")" 1 "lone directory is not nested under its own name"

run art 'd?'
ok "$(grep -c 's3://b/o/r/1/art/d1/' "$TMP/calls.log")" 1 "multiple dirs disambiguated by basename"

run art '*.diff'
ok "$(wc -l < "$TMP/calls.log")" 2 "glob uploads every match"

run art 'no-such-*' error;  ok "$RC" 1 "if-no-files-found=error fails the step"
run art 'no-such-*' ignore; ok "$RC" 0 "if-no-files-found=ignore passes"
run art 'no-such-*' warn;   ok "$RC" 0 "if-no-files-found=warn passes"

export CALLS="$TMP/calls.log"; : > "$CALLS"
PATH="$TMP/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_OUTPUT="$TMP/out" \
AWS_ACCESS_KEY_ID="" AWS_SECRET_ACCESS_KEY=s BUCKET=b ENDPOINT=https://e \
IN_NAME=art IN_PATH=single.log ON_MISSING=warn bash "$TMP/upload.sh" >/dev/null 2>&1
ok "$?" 1 "empty credentials fail loudly instead of uploading nothing"

[ "$fails" -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed"
exit "$fails"
