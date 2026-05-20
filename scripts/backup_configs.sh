#!/usr/bin/env bash
set -Eeuo pipefail

# Backup de configuraciones del homelab.
# Diseñado para cron: usa rutas absolutas, salida simple y falla de forma explicita.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/homelab/configs}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="homelab-configs-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "${name} debe ser un entero >= 0"
}

validate_positive_int "$RETENTION_DAYS" "RETENTION_DAYS"

mkdir -p "$BACKUP_DIR"
umask 077

tmp_list="$(mktemp)"
cleanup() {
  rm -f "$tmp_list"
}
trap cleanup EXIT

# Recolecta archivos a incluir:
# - docker/**/docker-compose.yml
# - docker/**/*.yml|yaml|json
# - scripts/*.sh
# Exclusiones:
# - */logs/*
# - */backups/*
# - docker/crafty/** excepto docker/crafty/docker-compose.yml
{
  if [[ -f "${REPO_ROOT}/docker/crafty/docker-compose.yml" ]]; then
    printf '%s\0' 'docker/crafty/docker-compose.yml'
  fi

  (cd "$REPO_ROOT" && find docker \
    \( -path 'docker/crafty' -o -path '*/logs' -o -path '*/backups' \) -prune -o \
    -type f \( -name 'docker-compose.yml' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' \) -print0)

  (cd "$REPO_ROOT" && find scripts -maxdepth 1 -type f -name '*.sh' -print0)
} | sort -zu > "$tmp_list"

[[ -s "$tmp_list" ]] || fail "No se encontraron archivos para respaldar"

log "Creando backup: $ARCHIVE_PATH"
(cd "$REPO_ROOT" && tar -czf "$ARCHIVE_PATH" --null --files-from "$tmp_list")

log "Aplicando retencion: ${RETENTION_DAYS} dias"
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'homelab-configs-*.tar.gz' -mtime "+${RETENTION_DAYS}" -print -delete || true

log "Backup completado correctamente"
