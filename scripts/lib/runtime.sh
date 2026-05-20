#!/usr/bin/env bash
set -Eeuo pipefail

# Logging simple con timestamp para tareas cron.
runtime_log() {
  printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

runtime_warn() {
  printf '[%s] [WARN] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

runtime_error() {
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# Inicializa lock exclusivo y timeout por defecto para el script.
init_runtime() {
  local script_name="${1:-}"
  local timeout_default="${2:-}"

  if [[ -z "$script_name" ]]; then
    runtime_error "Uso: init_runtime <script_name> [timeout_default]"
    exit 1
  fi

  LOCK_DIR="${LOCK_DIR:-/tmp/homelab-locks}"
  mkdir -p "$LOCK_DIR"

  local lock_file="$LOCK_DIR/${script_name}.lock"

  exec {RUNTIME_LOCK_FD}>"$lock_file"
  if ! flock -n "$RUNTIME_LOCK_FD"; then
    runtime_warn "Otro proceso de '$script_name' ya esta en ejecucion; se omite para evitar solape"
    exit 0
  fi

  if [[ -n "${SCRIPT_TIMEOUT_SEC:-}" ]]; then
    :
  elif [[ -n "$timeout_default" ]]; then
    SCRIPT_TIMEOUT_SEC="$timeout_default"
  else
    SCRIPT_TIMEOUT_SEC=""
  fi

  export LOCK_DIR SCRIPT_TIMEOUT_SEC RUNTIME_LOCK_FD
}

# Verifica dependencias requeridas por el script.
require_commands() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    runtime_error "Faltan comandos requeridos: ${missing[*]}"
    exit 1
  fi
}

# Ejecuta un comando con timeout si la utilidad existe.
with_timeout() {
  local seconds="${1:-}"
  shift || true

  if [[ -z "$seconds" ]]; then
    runtime_error "Uso: with_timeout <seconds> <cmd...>"
    exit 1
  fi

  if (( $# == 0 )); then
    runtime_error "Uso: with_timeout <seconds> <cmd...>"
    exit 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

# Ejecuta un comando usando SCRIPT_TIMEOUT_SEC cuando este definido.
run_with_script_timeout() {
  if (( $# == 0 )); then
    runtime_error "Uso: run_with_script_timeout <cmd...>"
    exit 1
  fi

  if [[ -n "${SCRIPT_TIMEOUT_SEC:-}" ]]; then
    with_timeout "$SCRIPT_TIMEOUT_SEC" "$@"
  else
    "$@"
  fi
}
