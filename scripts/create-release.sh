#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "create-release.sh has been replaced by publish-release.sh." >&2
exec "$SCRIPT_DIR/publish-release.sh" "$@"
