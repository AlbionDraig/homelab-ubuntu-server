#!/usr/bin/env bash
# Reporte operativo no destructivo:
# 1) Updates pendientes del sistema (si apt/apt-get existe)
# 2) Resumen de imagenes usadas por contenedores activos
# 3) Intento opcional de docker compose pull --dry-run por stack (si soportado)
#
# Diseniado para cron: salida clara, continua aunque una seccion no aplique.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

init_runtime "check_updates_report" 1800
require_commands date awk grep sort

echo "=== Check Updates Report ==="
echo "Fecha: $(date -Is)"
echo "Root: $ROOT_DIR"
echo

echo "--- Sistema: updates apt ---"
if command -v apt-get >/dev/null 2>&1; then
  # Simulacion segura para contar paquetes actualizables sin instalar nada.
  upgradable_count="$(run_with_script_timeout apt-get -s upgrade 2>/dev/null | awk '/^Inst /{count++} END{print count+0}')"
  echo "Paquetes upgradables (estimado): $upgradable_count"

  if command -v apt >/dev/null 2>&1; then
    echo "Detalle (apt list --upgradable):"
    apt list --upgradable 2>/dev/null || true
  fi
else
  echo "[INFO] apt/apt-get no disponible en este host"
fi

echo
echo "--- Docker: imagenes en uso por contenedores activos ---"
if command -v docker >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -q .; then
    echo "Nombre | Imagen | Status"
    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | sort
  else
    echo "[INFO] No hay contenedores activos"
  fi
else
  echo "[INFO] docker no disponible en PATH"
fi

echo
echo "--- Docker Compose: dry-run de pull por stack (opcional) ---"
if command -v docker >/dev/null 2>&1; then
  mapfile -t compose_files < <(run_with_script_timeout find "$ROOT_DIR/docker" -type f -name 'docker-compose.yml')
  if ((${#compose_files[@]} > 0)); then
    mapfile -t compose_files < <(printf '%s\n' "${compose_files[@]}" | sort)
  fi

  if ((${#compose_files[@]} == 0)); then
    echo "[INFO] No se encontraron docker-compose.yml para evaluar"
    exit 0
  fi

  if run_with_script_timeout docker compose pull --help 2>/dev/null | grep -q -- '--dry-run'; then
    for compose_file in "${compose_files[@]}"; do
      stack_name="$(basename "$(dirname "$compose_file")")"
      if run_with_script_timeout docker compose -f "$compose_file" pull --dry-run >/dev/null 2>&1; then
        echo "[OK]   $stack_name dry-run pull"
      else
        # No fallar el script: es reporte opcional.
        echo "[WARN] $stack_name no pudo ejecutar dry-run pull"
      fi
    done
  else
    echo "[INFO] docker compose pull --dry-run no soportado en esta version"
  fi
else
  echo "[INFO] docker no disponible; se omite prueba compose dry-run"
fi

echo
echo "[OK] Reporte completado"
