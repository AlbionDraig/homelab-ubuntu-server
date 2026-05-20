#!/bin/bash
# ---------------------------------------------------------
# 1. ACTUALIZACIÓN Y REPARACIÓN DE PAQUETES
# ---------------------------------------------------------
echo "---------------------------------------------------------"
echo "1. ACTUALIZACIÓN Y REPARACIÓN DE PAQUETES"
echo "---------------------------------------------------------"
apt-get update -y
apt-get install -f -y
dpkg --configure -a
apt-get autoremove -y
apt-get clean -y

# ---------------------------------------------------------
# 2. ANÁLISIS DE DISCOS Y REPARACIÓN AUTOMÁTICA
# ---------------------------------------------------------
echo "---------------------------------------------------------"
echo "2. ANÁLISIS DE DISCOS Y REPARACIÓN AUTOMÁTICA"
echo "---------------------------------------------------------"
# Instalar herramientas de diagnóstico de discos si no están
apt-get install smartmontools parted -y

echo "=== ANÁLISIS DE DISCOS: $(date) ==="

# Forzar chequeo automático de archivos (FSCK) en el próximo reinicio de forma desatendida
tune2fs -c 1 /dev/sda1 2>/dev/null || true

# Analizar la salud física de los discos (S.M.A.R.T.)
for disco in $(lsblk -dno NAME | grep -E '^sd|^nvme'); do
    echo "Salud del disco /dev/$disco:"
    smartctl -H /dev/$disco | grep -E "result|PASSED|FAILED"
done

# Reparar errores leves de sectores lógicos corruptos (si el disco se puede poner en solo lectura)
# Nota: Si /dev/sda1 es tu raíz, el sistema se congelará momentáneamente para repararse de forma segura.
echo "=== REPARAR ERRORES LEVES DE SECTORES LÓGICOS CORRUPTOS ==="
fsck -a -A -y 2>/dev/null || true

