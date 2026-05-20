#!/usr/bin/env bash
# Auditoria no destructiva de baseline de seguridad para este homelab.
# - Revisa docker/**/docker-compose.yml en busca de:
#   * privileged: true (riesgo alto)
#   * network_mode: host (riesgo medio)
#   * lineas ports: (observacion)
# - Revisa estado de UFW si el comando existe
# - Revisa PermitRootLogin en /etc/ssh/sshd_config si existe
#
# Exit codes:
# - 1: se detectan riesgos altos (privileged: true o PermitRootLogin yes)
# - 0: sin riesgos altos (aunque puede haber observaciones)

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

init_runtime "security_baseline_audit" 900
require_commands find sort grep awk tail head

echo "=== Security Baseline Audit ==="
echo "Fecha: $(date -Is)"
echo "Root: $ROOT_DIR"
echo

if [[ ! -d "$ROOT_DIR/docker" ]]; then
  echo "[WARN] No existe directorio docker en $ROOT_DIR"
  exit 0
fi

mapfile -t compose_files < <(run_with_script_timeout find "$ROOT_DIR/docker" -type f -name 'docker-compose.yml')
if ((${#compose_files[@]} > 0)); then
  mapfile -t compose_files < <(printf '%s\n' "${compose_files[@]}" | sort)
fi

if ((${#compose_files[@]} == 0)); then
  echo "[WARN] No se encontraron docker-compose.yml bajo $ROOT_DIR/docker"
  exit 0
fi

high_risk_found=0
network_host_found=0
ports_observed=0

for compose_file in "${compose_files[@]}"; do
  stack_name="$(basename "$(dirname "$compose_file")")"

  privileged_hits="$(grep -nEi '^[[:space:]]*privileged:[[:space:]]*true([[:space:]]*#.*)?$' "$compose_file" || true)"
  if [[ -n "$privileged_hits" ]]; then
    echo "[HIGH] $stack_name | privileged: true detectado en $compose_file"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "       $line"
    done <<< "$privileged_hits"
    high_risk_found=1
  fi

  host_net_hits="$(grep -nEi '^[[:space:]]*network_mode:[[:space:]]*["'"']?host["'"']?([[:space:]]*#.*)?$' "$compose_file" || true)"
  if [[ -n "$host_net_hits" ]]; then
    echo "[WARN] $stack_name | network_mode: host detectado en $compose_file"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "       $line"
    done <<< "$host_net_hits"
    network_host_found=1
  fi

  ports_hits="$(grep -nEi '^[[:space:]]*ports:[[:space:]]*($|#)' "$compose_file" || true)"
  if [[ -n "$ports_hits" ]]; then
    echo "[OBS]  $stack_name | lineas ports detectadas en $compose_file"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "       $line"
    done <<< "$ports_hits"
    ports_observed=1
  fi
done

echo
if command -v ufw >/dev/null 2>&1; then
  ufw_status_line="$(ufw status 2>/dev/null | head -n 1 || true)"
  if [[ -n "$ufw_status_line" ]]; then
    echo "[INFO] UFW: $ufw_status_line"
  else
    echo "[WARN] UFW instalado pero no se pudo leer su estado"
  fi
else
  echo "[INFO] UFW no esta instalado o no esta en PATH"
fi

sshd_config="/etc/ssh/sshd_config"
if [[ -f "$sshd_config" ]]; then
  permit_root_value="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*PermitRootLogin[[:space:]]+/ {
      v=$2
      gsub(/[[:space:]]+/, "", v)
      print tolower(v)
      found=1
    }
    END {
      if (!found) {
        print "not-set"
      }
    }
  ' "$sshd_config" | tail -n 1)"

  case "$permit_root_value" in
    yes)
      echo "[HIGH] PermitRootLogin yes en $sshd_config"
      high_risk_found=1
      ;;
    no|prohibit-password|without-password|forced-commands-only)
      echo "[OK]   PermitRootLogin $permit_root_value en $sshd_config"
      ;;
    not-set)
      echo "[WARN] PermitRootLogin no esta definido explicitamente en $sshd_config"
      ;;
    *)
      echo "[WARN] Valor inesperado de PermitRootLogin ('$permit_root_value') en $sshd_config"
      ;;
  esac
else
  echo "[INFO] No existe $sshd_config, se omite validacion de SSH"
fi

echo
if ((high_risk_found == 1)); then
  echo "[FAIL] Se detectaron riesgos altos en el baseline de seguridad"
  exit 1
fi

if ((network_host_found == 1 || ports_observed == 1)); then
  echo "[OK] Sin riesgos altos. Hay advertencias/observaciones para revisar"
else
  echo "[OK] Baseline sin hallazgos relevantes"
fi
