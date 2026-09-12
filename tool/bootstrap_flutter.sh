#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_directory="$repository_root/.tooling/flutter"
flutter_binary="$flutter_directory/bin/flutter"

if [[ ! -d "$flutter_directory/.git" ]]; then
  mkdir -p "$(dirname "$flutter_directory")"
  git clone --depth 1 --branch 3.47.4 --single-branch \
    https://github.com/flutter/flutter.git "$flutter_directory"
fi

flutter_version="$($flutter_binary --version)"
if [[ "$flutter_version" != *"Flutter 3.47.4"* ]]; then
  printf 'Expected Flutter 3.47.4, but found:\n%s\n' "$flutter_version" >&2
  exit 1
fi

"$flutter_binary" precache --web
