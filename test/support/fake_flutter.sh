#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  --version)
    printf '%s\n' "${FAKE_FLUTTER_VERSION:?FAKE_FLUTTER_VERSION is required}"
    ;;
  precache)
    [[ "${2:-}" == '--web' ]]
    ;;
  *)
    printf 'Unexpected fake Flutter command: %s\n' "$*" >&2
    exit 2
    ;;
esac
