#!/usr/bin/env bash
# Runs the path-handling self-check that lives next to the action, so CI runs it too.
exec "$(dirname "$0")/../actions/upload-s3/test.sh"
