#!/usr/bin/env bash
# The path-matching half of actions/upload-s3, run with and without globstar.
# It exists because macOS ships bash 3.2, GitHub runs `run:` blocks under
# `bash -e`, and `shopt -s globstar` there does not warn — it ends the step. The
# action was unusable on every macOS runner until that was found the slow way.
#
#   ./tests/test-upload-s3-glob.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Pull the matching block out of the action so there is no second copy to rot.
python3 - "$WORK/match.sh" <<'PY'
import sys, pathlib
y = pathlib.Path('actions/upload-s3/action.yml').read_text()
body = y.split('        shopt -s nullglob\n', 1)[1]
block = '        shopt -s nullglob\n' + body.split('        if [ "${HAVE_GLOBSTAR}" -eq 1 ]; then shopt -u globstar; fi\n')[0] \
        + '        if [ "${HAVE_GLOBSTAR}" -eq 1 ]; then shopt -u globstar; fi\n'
pathlib.Path(sys.argv[1]).write_text(
    "\n".join(l[8:] for l in block.splitlines()) + '\nprintf "%s\\n" "${MATCHES[@]}"\n')
PY

mkdir -p "$WORK/out/a/b"
: > "$WORK/out/top.log"
: > "$WORK/out/a/b/deep.log"

run() {  # $1 = IN_PATH, $2 = "nobash4" to simulate bash 3.2
  local pre=""
  [ "${2:-}" = nobash4 ] && pre='shopt() { [ "$1" = -s ] && [ "$2" = globstar ] && return 1; builtin shopt "$@"; };'
  ( cd "$WORK" && IN_PATH="$1" bash -e -o pipefail -c "$pre $(cat "$WORK/match.sh")" ) 2>&1
}

# bash 4+: ** recurses, as actions/upload-artifact users expect.
got=$(run 'out/**/*.log') || { echo "FAIL: globstar path errored"; exit 1; }
grep -q 'out/a/b/deep.log' <<<"$got" || { echo "FAIL: ** did not recurse: $got"; exit 1; }
echo "  ok: ** recurses when globstar is available"

# bash 3.2 + a plain path: must still work — this is the macOS case that was dead.
got=$(run 'out/top.log' nobash4) || { echo "FAIL: plain path died without globstar"; echo "$got"; exit 1; }
[ "$got" = "out/top.log" ] || { echo "FAIL: wrong match without globstar: $got"; exit 1; }
echo "  ok: a plain path still uploads on bash 3.2"

# bash 3.2 + a ** path: must refuse loudly, not upload a silent subset.
if got=$(run 'out/**/*.log' nobash4); then
  echo "FAIL: ** without globstar should have failed, got: $got"; exit 1
fi
grep -q '::error::' <<<"$got" || { echo "FAIL: no actionable error: $got"; exit 1; }
echo "  ok: ** without globstar refuses, and says why"

echo "ok: upload-s3 path matching survives bash 3.2"
