#!/usr/bin/env bash
# Revisa expiracion de certificados TLS locales para alertas preventivas.
# - Busca certificados en docker/**/certs, docker/**/certificates y /etc/ssl/certs (si es accesible)
# - Umbral configurable por DAYS_WARN (default: 30)
# - Devuelve exit 1 si encuentra certificados que vencen dentro del umbral
#
# Script no destructivo y apto para cron: salida clara con [INFO]/[WARN]/[OK]/[ERROR].

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAYS_WARN="${DAYS_WARN:-30}"

if ! [[ "$DAYS_WARN" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] DAYS_WARN debe ser un entero >= 0. Valor recibido: $DAYS_WARN"
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[ERROR] openssl no esta disponible en PATH"
  exit 2
fi

if ! command -v date >/dev/null 2>&1; then
  echo "[ERROR] date no esta disponible en PATH"
  exit 2
fi

declare -A seen_paths=()
declare -a cert_files=()

add_candidate_certs_from_dir() {
  local base_dir="$1"

  if [[ ! -d "$base_dir" ]]; then
    return 0
  fi

  if [[ ! -r "$base_dir" || ! -x "$base_dir" ]]; then
    echo "[INFO] Directorio sin permisos de lectura/recorrido, se omite: $base_dir"
    return 0
  fi

  while IFS= read -r -d '' file_path; do
    # Evita procesar rutas repetidas (por enlaces o coincidencias superpuestas).
    if [[ -n "${seen_paths["$file_path"]+x}" ]]; then
      continue
    fi
    seen_paths["$file_path"]=1

    # Solo agrega archivos que openssl reconoce como certificado X.509.
    if openssl x509 -in "$file_path" -noout >/dev/null 2>&1; then
      cert_files+=("$file_path")
    fi
  done < <(find -L "$base_dir" -type f -print0 2>/dev/null)
}

echo "=== Check TLS Expiry ==="
echo "Fecha: $(date -Is)"
echo "Root: $ROOT_DIR"
echo "DAYS_WARN: $DAYS_WARN"
echo

# 1) Directorios de certificados dentro de docker/**/certs y docker/**/certificates
while IFS= read -r -d '' cert_dir; do
  add_candidate_certs_from_dir "$cert_dir"
done < <(find "$ROOT_DIR/docker" -type d \( -name certs -o -name certificates \) -print0 2>/dev/null)

# 2) Certificados locales del sistema, solo si el directorio existe y es accesible.
add_candidate_certs_from_dir "/etc/ssl/certs"

if ((${#cert_files[@]} == 0)); then
  echo "[INFO] No se encontraron certificados X.509 en rutas objetivo"
  exit 0
fi

warn_found=0
threshold_seconds=$((DAYS_WARN * 86400))
current_epoch="$(date -u +%s)"

echo "[INFO] Certificados detectados: ${#cert_files[@]}"

for cert_path in "${cert_files[@]}"; do
  enddate_line="$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null || true)"

  if [[ -z "$enddate_line" || "$enddate_line" != notAfter=* ]]; then
    echo "[WARN] No se pudo leer fecha de expiracion: $cert_path"
    warn_found=1
    continue
  fi

  not_after="${enddate_line#notAfter=}"
  expiry_epoch="$(date -u -d "$not_after" +%s 2>/dev/null || true)"

  if [[ -z "$expiry_epoch" ]]; then
    echo "[WARN] Fecha de expiracion no parseable para: $cert_path | notAfter=$not_after"
    warn_found=1
    continue
  fi

  remaining_seconds=$((expiry_epoch - current_epoch))
  remaining_days=$((remaining_seconds / 86400))

  if openssl x509 -in "$cert_path" -noout -checkend "$threshold_seconds" >/dev/null 2>&1; then
    echo "[OK]   $cert_path | vence en ${remaining_days} dias | notAfter=$not_after"
  else
    echo "[WARN] $cert_path | vence en ${remaining_days} dias (<= $DAYS_WARN) | notAfter=$not_after"
    warn_found=1
  fi
done

if ((warn_found == 1)); then
  echo "[FAIL] Hay certificados vencidos o proximos a vencer dentro de $DAYS_WARN dias"
  exit 1
fi

echo "[OK] No hay certificados dentro del umbral de alerta"
