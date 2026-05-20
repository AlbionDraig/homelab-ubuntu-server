#!/usr/bin/env bash
# Mantenimiento seguro para Ubuntu Server.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

log_info() {
    echo "[$(date '+%F %T')] [INFO] $*"
}

log_warn() {
    echo "[$(date '+%F %T')] [WARN] $*" >&2
}

log_error() {
    echo "[$(date '+%F %T')] [ERROR] $*" >&2
}

on_error() {
    local line="$1"
    log_error "Fallo en la linea ${line}."
}

trap 'on_error ${LINENO}' ERR

init_runtime "mantenimiento" 5400
require_commands apt-get dpkg findmnt lsblk grep

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root."
        exit 1
    fi
}

actualizar_y_reparar_paquetes() {
    log_info "---------------------------------------------------------"
    log_info "1. ACTUALIZACION Y REPARACION DE PAQUETES"
    log_info "---------------------------------------------------------"

    run_with_script_timeout apt-get update -y
    run_with_script_timeout apt-get install -f -y
    dpkg --configure -a
    run_with_script_timeout apt-get autoremove -y
    run_with_script_timeout apt-get clean -y
}

instalar_herramientas_disco() {
    # Dependencias para diagnostico y metadatos de disco.
    run_with_script_timeout apt-get install -y smartmontools parted
}

get_root_device() {
    # Detecta el dispositivo real montado en /.
    findmnt -nro SOURCE /
}

programar_fsck_proximo_reinicio() {
    local root_device root_fstype

    root_device="$(get_root_device)"
    root_fstype="$(findmnt -nro FSTYPE /)"

    log_info "Raiz detectada: ${root_device} (${root_fstype})"

    # Solo ext2/3/4 en /dev/* soporta tune2fs; otros FS usan fallback.
    if [[ "${root_fstype}" =~ ^ext[2-4]$ ]] \
        && [[ "${root_device}" == /dev/* ]] \
        && command -v tune2fs >/dev/null 2>&1; then
        tune2fs -c 1 "${root_device}"
        log_info "FSCK programado con tune2fs para el proximo reinicio."
    else
        touch /forcefsck
        log_warn "No se pudo usar tune2fs (FS no ext, origen no /dev o comando ausente). Se creo /forcefsck."
    fi
}

analizar_salud_smart() {
    local disco

    log_info "=== ANALISIS SMART DE DISCOS: $(date '+%F %T') ==="
    while IFS= read -r disco; do
        [[ -z "${disco}" ]] && continue
        log_info "Salud del disco /dev/${disco}:"
        if ! run_with_script_timeout smartctl -H "/dev/${disco}" | grep -E "result|PASSED|FAILED"; then
            log_warn "No se pudo obtener estado SMART resumido para /dev/${disco}."
        fi
    done < <(lsblk -dno NAME | grep -E '^(sd|nvme)')
}

main() {
    require_root

    actualizar_y_reparar_paquetes

    log_info "---------------------------------------------------------"
    log_info "2. ANALISIS DE DISCOS Y PROGRAMACION DE FSCK"
    log_info "---------------------------------------------------------"

    instalar_herramientas_disco
    programar_fsck_proximo_reinicio
    analizar_salud_smart

    # No se ejecuta fsck en caliente para evitar riesgo operativo.
    log_info "Mantenimiento completado. El chequeo de FS quedo programado para reinicio."
}

main "$@"

