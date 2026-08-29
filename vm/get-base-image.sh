#!/bin/bash
# Fetch the project-pinned base image and verify it.
# Pinned build: Debian 12 (bookworm) 20260806-2562 — the exact build whose
# official manifest is committed as vm/SHA512SUMS (filenames normalized:
# date suffix stripped).
# Source: https://cdimage.debian.org/cdimage/cloud/bookworm/20260806-2562/
# Idempotent: no-ops if the local file already verifies.
set -euo pipefail
cd "$(dirname "$0")"

BUILD=20260806-2562
BASE_URL="https://cdimage.debian.org/cdimage/cloud/bookworm/$BUILD"
FILE=debian-12-generic-amd64.qcow2

if [ -f "$FILE" ] && sha512sum -c SHA512SUMS --ignore-missing 2>/dev/null | grep -q "^$FILE: OK"; then
  echo "$FILE already present and verified — nothing to do"
  exit 0
fi

echo "Downloading $FILE (~430 MB) from $BASE_URL ..."
curl -fL --retry 3 --progress-bar -o "$FILE" \
  "$BASE_URL/debian-12-generic-amd64-$BUILD.qcow2"

# Cross-check against the build's live manifest (suffixed filenames),
# then against the committed normalized manifest.
curl -fsSL "$BASE_URL/SHA512SUMS" -o .sha512sums-remote
grep "debian-12-generic-amd64-$BUILD.qcow2" .sha512sums-remote | sha512sum -c -
rm -f .sha512sums-remote
sha512sum -c SHA512SUMS --ignore-missing

echo "OK: $FILE downloaded and SHA512-verified"
