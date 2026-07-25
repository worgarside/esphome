#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "${repo_root}"

if [[ ! -f secrets.yaml ]]; then
  if [[ ! -f secrets.yaml.example ]]; then
    echo "Missing secrets.yaml and secrets.yaml.example." >&2
    exit 1
  fi
  cp secrets.yaml.example secrets.yaml
  echo "Created secrets.yaml from secrets.yaml.example for validation."
fi

shopt -s nullglob
configs=(esp32-*.yaml)
if ((${#configs[@]} == 0)); then
  echo "No esp32-*.yaml device configs found." >&2
  exit 1
fi

if ! command -v esphome >/dev/null 2>&1; then
  echo "esphome was not found on PATH." >&2
  exit 1
fi

status=0
for config in "${configs[@]}"; do
  echo "Validating ${config}"
  if ! esphome config "${config}"; then
    status=1
  fi
done

exit "${status}"
