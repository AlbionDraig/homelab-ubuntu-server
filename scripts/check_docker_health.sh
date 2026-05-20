#!/usr/bin/env bash
# Revisa salud operativa de contenedores por stack Compose.
# - Recorre docker/*/docker-compose.yml
# - Lista contenedores, estado y health (si existe)
# - Devuelve exit 1 si encuentra exited, dead o unhealthy
#
# Diseniado para ejecucion automatica (cron): salida clara y sin cambios destructivos.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_GLOB="$ROOT_DIR/docker/*/docker-compose.yml"

init_runtime "check_docker_health" 600
require_commands docker

shopt -s nullglob
compose_files=($COMPOSE_GLOB)
shopt -u nullglob

if ((${#compose_files[@]} == 0)); then
  echo "[WARN] No se encontraron archivos docker-compose.yml en $ROOT_DIR/docker/*/"
  exit 0
fi

bad_found=0

echo "=== Check Docker Health ==="
echo "Fecha: $(date -Is)"
echo "Root: $ROOT_DIR"
echo

for compose_file in "${compose_files[@]}"; do
  stack_dir="$(dirname "$compose_file")"
  stack_name="$(basename "$stack_dir")"

  echo "--- Stack: $stack_name ---"

  # -a incluye contenedores detenidos para detectar exited/dead.
  mapfile -t container_ids < <(run_with_script_timeout docker compose -f "$compose_file" ps -aq 2>/dev/null || true)

  if ((${#container_ids[@]} == 0)); then
    echo "[INFO] Sin contenedores creados en este stack"
    echo
    continue
  fi

  for cid in "${container_ids[@]}"; do
    # Health puede no existir segun la imagen; se muestra como n/a.
    line="$(run_with_script_timeout docker inspect --format '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$cid" 2>/dev/null || true)"

    if [[ -z "$line" ]]; then
      echo "[WARN] No se pudo inspeccionar contenedor $cid"
      bad_found=1
      continue
    fi

    name="${line%%|*}"
    rest="${line#*|}"
    state="${rest%%|*}"
    health="${rest#*|}"
    name="${name#/}"

    printf '  - %s | state=%s | health=%s\n' "$name" "$state" "$health"

    if [[ "$state" == "exited" || "$state" == "dead" || "$health" == "unhealthy" ]]; then
      bad_found=1
    fi
  done

  echo

done

if ((bad_found == 1)); then
  echo "[FAIL] Se detectaron contenedores en estado exited/dead o health=unhealthy"
  exit 1
fi

echo "[OK] No se detectaron estados criticos"
