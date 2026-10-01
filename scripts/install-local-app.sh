#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
./scripts/build-app.sh
DEST_APP="${HOME}/Applications/Pipet.app"
mkdir -p "${HOME}/Applications"
if [[ -e "${DEST_APP}" ]]; then
  if [[ "${1:-}" != "--replace" ]]; then
    echo "Pipet is already installed. Use --replace to keep a backup and update it." >&2
    exit 1
  fi
  RUNNING_PIDS="$(pgrep -f "^${DEST_APP}/Contents/MacOS/Pipet( |$)" || true)"
  if [[ -n "${RUNNING_PIDS}" ]]; then
    while IFS= read -r APP_PID; do
      kill "${APP_PID}"
      for ((ATTEMPT=0; ATTEMPT<50; ATTEMPT++)); do
        if ! kill -0 "${APP_PID}" 2>/dev/null; then break; fi
        sleep 0.1
      done
      if kill -0 "${APP_PID}" 2>/dev/null; then
        echo "Pipet did not quit. Close it before installing the update." >&2
        exit 1
      fi
    done <<< "${RUNNING_PIDS}"
  fi
  BACKUP_DIR="${ROOT_DIR}/.build/backups/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "${BACKUP_DIR}"
  mv "${DEST_APP}" "${BACKUP_DIR}/Pipet.app"
fi
ditto .build/Pipet.app "${DEST_APP}"
open "${DEST_APP}"
echo "Installed to ${DEST_APP}"
if [[ "${1:-}" == "--replace" ]]; then
  echo "With local signing, a new build may need the old Accessibility entry removed and the installed app added again."
fi
