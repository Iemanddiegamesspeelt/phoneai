#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install via: brew install xcodegen"
  exit 1
fi
xcodegen generate --spec project.yml
echo "Project generated at $(pwd)/PocketAI.xcodeproj"
