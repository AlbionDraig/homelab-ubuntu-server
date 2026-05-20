#!/usr/bin/env bash
set -Eeuo pipefail

# Verifica el backup mas reciente con prueba real de restauracion en temporal.
# Diseñado para cron: resultado claro OK/FAIL y limpieza automatica.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

init_runtime "verify_backup_restore" 1800
require_commands find sort head cut tar mktemp rm

BACKUP_DIR="${BACKUP_DIR:-/var/backups/homelab/configs}"

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "FAIL: $*"
  exit 1
}

[[ -d "$BACKUP_DIR" ]] || fail "BACKUP_DIR no existe: $BACKUP_DIR"

latest_backup="$(run_with_script_timeout find "$BACKUP_DIR" -maxdepth 1 -type f -name 'homelab-configs-*.tar.gz' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
[[ -n "$latest_backup" ]] || fail "No se encontraron backups en $BACKUP_DIR"

log "Backup mas reciente: $latest_backup"
log "Verificando integridad tar -tzf"
run_with_script_timeout tar -tzf "$latest_backup" >/dev/null

tmp_restore_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_restore_dir"
}
trap cleanup EXIT

log "Probando extraccion en temporal: $tmp_restore_dir"
run_with_script_timeout tar -xzf "$latest_backup" -C "$tmp_restore_dir"

log "OK: verificacion de restore completada"
