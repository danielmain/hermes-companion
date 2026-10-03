#!/usr/bin/env bash
set -euo pipefail

HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-/Users/daniel/Workspace/hermes-agent}"
TARGET_DIR="${HERMES_AGENT_DIR}/optional-skills/health/hermes-companion"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/hermes-companion" && pwd)"

if [ ! -d "${TARGET_DIR}" ]; then
  echo "Error: target skill directory does not exist: ${TARGET_DIR}" >&2
  exit 1
fi

echo "Syncing ${SOURCE_DIR}/ -> ${TARGET_DIR}/ ..."
rsync -av --delete --exclude="__pycache__" --exclude=".DS_Store" "${SOURCE_DIR}/" "${TARGET_DIR}/"

echo "Running tests in ${TARGET_DIR} ..."
python3 "${TARGET_DIR}/scripts/test_companion.py"

echo "Sync complete and verified."
