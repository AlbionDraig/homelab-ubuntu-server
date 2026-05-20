#!/usr/bin/env bash
set -Eeuo pipefail

# Rotacion/limpieza de logs apta para cron.
# - Elimina .log antiguos segun retencion.
# - Comprime logs grandes opcionalmente.
# - Tolera rutas inexistentes sin fallar.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
MAX_SIZE_MB="${MAX_SIZE_MB:-20}"
COMPRESS_LARGE_LOGS="${COMPRESS_LARGE_LOGS:-1}"

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || {
    log "ERROR: ${name} debe ser un entero >= 0"
    exit 1
  }
}

validate_positive_int "$LOG_RETENTION_DAYS" "LOG_RETENTION_DAYS"
validate_positive_int "$MAX_SIZE_MB" "MAX_SIZE_MB"

log_paths=("/var/log/homelab")
for d in "$REPO_ROOT"/docker/*/logs; do
  [[ -d "$d" ]] && log_paths+=("$d")
done

for path in "${log_paths[@]}"; do
  if [[ ! -d "$path" ]]; then
    log "Ruta no existe, se omite: $path"
    continue
  fi

  log "Limpieza de logs antiguos en: $path"
  find "$path" -type f -name '*.log' -mtime "+${LOG_RETENTION_DAYS}" -print -delete || true

  if [[ "$COMPRESS_LARGE_LOGS" == "1" ]]; then
    log "Compresion de logs grandes (> ${MAX_SIZE_MB} MB) en: $path"
    while IFS= read -r -d '' file; do
      gzip -f "$file"
      log "Comprimido: ${file}.gz"
    done < <(find "$path" -type f -name '*.log' -size "+${MAX_SIZE_MB}M" -print0)
  fi
done

log "Rotacion/limpieza finalizada"
