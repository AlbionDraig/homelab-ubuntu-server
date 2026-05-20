#!/usr/bin/env bash
# Valida sintaxis de todos los docker-compose.yml bajo docker/.
# Ejecuta: docker compose -f <file> config >/dev/null
# Reporta OK/FAIL por stack y devuelve exit 1 si alguno falla.
#
# Script no destructivo, apto para cron/CI.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

init_runtime "validate_compose_all" 900
require_commands docker find sort

mapfile -t compose_files < <(run_with_script_timeout find "$ROOT_DIR/docker" -type f -name 'docker-compose.yml')
if ((${#compose_files[@]} > 0)); then
  mapfile -t compose_files < <(printf '%s\n' "${compose_files[@]}" | sort)
fi

if ((${#compose_files[@]} == 0)); then
  echo "[WARN] No se encontraron docker-compose.yml en $ROOT_DIR/docker"
  exit 0
fi

failed=0

echo "=== Validate Compose Files ==="
echo "Fecha: $(date -Is)"
echo "Root: $ROOT_DIR"
echo

for compose_file in "${compose_files[@]}"; do
  stack_name="$(basename "$(dirname "$compose_file")")"

  if run_with_script_timeout docker compose -f "$compose_file" config >/dev/null 2>&1; then
    echo "[OK]   $stack_name ($compose_file)"
  else
    echo "[FAIL] $stack_name ($compose_file)"
    failed=1
  fi
done

echo
if ((failed == 1)); then
  echo "[FAIL] Uno o mas stacks no pasaron validacion de compose"
  exit 1
fi

echo "[OK] Todos los stacks pasaron validacion"
