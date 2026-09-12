#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_flutter="$project_root/test/support/fake_flutter.sh"

run_bootstrap_with_version() (
  fixture_root="$(mktemp -d)"
  trap 'rm -rf "$fixture_root"' EXIT

  mkdir -p "$fixture_root/tool" "$fixture_root/.tooling/flutter/.git" \
    "$fixture_root/.tooling/flutter/bin"
  cp "$project_root/tool/bootstrap_flutter.sh" \
    "$fixture_root/tool/bootstrap_flutter.sh"
  ln -s "$fake_flutter" "$fixture_root/.tooling/flutter/bin/flutter"

  FAKE_FLUTTER_VERSION="$1" "$fixture_root/tool/bootstrap_flutter.sh"
)

failures=0

expect_rejected() {
  local description="$1"
  local version="$2"

  if run_bootstrap_with_version "$version"; then
    printf 'FAIL: bootstrap accepted %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

expect_accepted() {
  local version="$1"

  if ! run_bootstrap_with_version "$version"; then
    printf 'FAIL: bootstrap rejected the exact required toolchain\n' >&2
    failures=$((failures + 1))
  fi
}

expect_rejected \
  'a prefix-sharing Flutter version' \
  $'Flutter 3.47.40 • channel stable\nTools • Dart 3.13.3'
expect_rejected \
  'an incorrect Dart version' \
  $'Flutter 3.47.4 • channel stable\nTools • Dart 3.13.4'
expect_accepted \
  $'Flutter 3.47.4 • channel stable\nTools • Dart 3.13.3'

if (( failures > 0 )); then
  exit 1
fi

printf 'Bootstrap version validation tests passed.\n'
