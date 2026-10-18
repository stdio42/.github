#!/usr/bin/env bash
# The "Ensure aws CLI" step of actions/upload-s3, run for real in the slim images
# callers use as `container:`. ubuntu:24.04 dropped the awscli package, so the
# apt path failed there and took navit's win32 upload with it (stdio42/navit#73).
#
#   ./tests/test-upload-s3-install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "SKIP: docker required"; exit 0; }

# Pull the step out of the action so there is no second copy to rot.
STEP="$(python3 -c "
import yaml
print(yaml.safe_load(open('actions/upload-s3/action.yml'))['runs']['steps'][0]['run'])
")"

for image in ubuntu:24.04 debian:stable-slim; do
  echo "--- $image"
  docker run --rm "$image" bash -c "$STEP" | tail -1 | grep -q '^aws-cli/' \
    || { echo "FAIL: no aws CLI after install step in $image"; exit 1; }
done
echo "OK"
