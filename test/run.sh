#!/usr/bin/env bash
# Run every kwt test file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
status=0
for f in "$here"/*_test.sh; do
  printf '\n== %s ==\n' "$(basename "$f")"
  if ! bash "$f"; then status=1; fi
done
exit "$status"
