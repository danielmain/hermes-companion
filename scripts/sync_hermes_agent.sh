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

# Check for git changes in hermes-agent repo and auto commit & push
if [ -d "${HERMES_AGENT_DIR}/.git" ]; then
  CHANGES=$(git -C "${HERMES_AGENT_DIR}" status --porcelain "optional-skills/health/hermes-companion" || true)
  if [ -n "${CHANGES}" ]; then
    echo "Changes detected in hermes-agent fork. Committing and pushing..."
    MSG="${1:-feat(skills): sync hermes-companion skill updates}"
    git -C "${HERMES_AGENT_DIR}" add "optional-skills/health/hermes-companion"
    git -C "${HERMES_AGENT_DIR}" commit -m "${MSG}"
    git -C "${HERMES_AGENT_DIR}" push origin feat/hermes-companion-skill
    echo "Successfully pushed to hermes-agent:feat/hermes-companion-skill"
  else
    echo "Fork is already in sync with upstream branch."
  fi
fi
