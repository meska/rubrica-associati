#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly flutter_root="${FLUTTER_ROOT:-/opt/flutter}"
readonly flutter_bin="$flutter_root/bin/flutter"

# Se manca Flutter, fermarse qua xe meio che produrre cartelle mezze vote.
if [[ ! -x "$flutter_bin" ]]; then
  echo "Flutter non trovato in $flutter_bin" >&2
  exit 1
fi

cd "$repo_root"
GENERATE_STORE_SCREENSHOTS=1 FLUTTER_ROOT="$flutter_root" \
  "$flutter_bin" test test/mobile_store_screenshot_test.dart
