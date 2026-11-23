#!/usr/bin/env bash
set -Eeuo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
exec bash "$source_dir/deploy/release/install.sh" "$@"
