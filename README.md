# Homelab Ubuntu Server

Guia completa para desplegar y operar este repositorio en una maquina nueva con Ubuntu Server.

## Objetivo del proyecto

Este proyecto centraliza un homelab basado en Docker Compose con foco en:

- Observabilidad: Prometheus, Grafana, Loki, Promtail, Node Exporter, cAdvisor.
- Acceso y routing: Traefik.
- Seguridad y auditoria: CrowdSec + scripts de baseline.
- Operacion y mantenimiento: backups, health checks, validacion de compose, rotacion de logs y cron.
- Servicios de utilidad: Homepage, Uptime Kuma, Crafty.

## Stacks incluidos (servicio / puerto)

| Stack | Servicio | Puerto host -> contenedor | Nota |
|---|---|---|---|
| traefik | traefik | 80 -> 80, 8080 -> 8080 | Entrada HTTP + dashboard |
| grafana | grafana | 3000 -> 3000 | Visualizacion |
| prometheus | prometheus | 9090 -> 9090 | Metricas |
| loki | loki | 3100 -> 3100 | Logs |
| promtail | promtail | N/A | Recolector de logs (sin puerto publicado) |
| node-exporter | node-exporter | 9100 -> 9100 | Metricas del host |
| cadvisor | cadvisor | 8088 -> 8080 | Metricas de contenedores |
| crowdsec | crowdsec | 8081 -> 8080 | Seguridad |
| homepage | homepage | 3002 -> 3000 | Portal de servicios |
| uptime-kuma | uptime-kuma | 3001 -> 3001 | Monitoreo de disponibilidad |
| crafty | crafty | 8443 -> 8443, 8123 -> 8123, 25565 -> 25565 | Panel y servicio de juego |

## Requisitos previos del host

- Ubuntu Server 22.04 LTS o 24.04 LTS.
- Usuario con privilegios sudo.
- Conectividad a Internet para instalar paquetes e imagenes Docker.
- Puertos abiertos en firewall segun servicios que quieras exponer.
- Espacio en disco para imagenes, volumenes y backups.

## Instalacion de Docker Engine + Compose plugin + git + cron + utilidades

Ejecuta como usuario con sudo:

~~~bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  git cron openssl tar gzip findutils coreutils gawk grep util-linux

sudo systemctl enable --now docker
sudo systemctl enable --now cron

sudo usermod -aG docker $USER
~~~

Aplica grupo docker en la sesion actual (sin reiniciar):

~~~bash
newgrp docker
docker --version
docker compose version
~~~

## Clonado del repo en /opt/homelab-ubuntu-server

Si ya tienes el repositorio remoto:

~~~bash
sudo mkdir -p /opt
sudo chown $USER:$USER /opt
git clone REEMPLAZA_CON_URL_REAL_DEL_REPO /opt/homelab-ubuntu-server
cd /opt/homelab-ubuntu-server
~~~

Recomendacion: manten el repositorio con propietario del usuario operador para facilitar actualizaciones, validaciones y tareas operativas sin friccion.

### Datos no versionados

Los datos de runtime, logs y backups no se versionan en Git (especialmente los de `docker/crafty`). En una maquina nueva se crean vacios durante el despliegue inicial; si necesitas continuidad operativa, restaura esos datos manualmente desde tus respaldos.

## Preparacion de permisos y directorios

Crear rutas operativas usadas por scripts:

~~~bash
sudo mkdir -p /var/log/homelab
sudo mkdir -p /var/lock/homelab
sudo mkdir -p /var/backups/homelab/configs

sudo chown -R root:root /var/log/homelab /var/lock/homelab /var/backups/homelab
sudo chmod 0755 /var/log/homelab /var/lock/homelab /var/backups/homelab
~~~

Permisos de scripts:

~~~bash
cd /opt/homelab-ubuntu-server
chmod +x scripts/*.sh
~~~

Crear red externa esperada por los compose (si no existe):

~~~bash
docker network create proxy || true
~~~

## Validacion de compose de todos los stacks

Validacion recomendada con script del repo:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/validate_compose_all.sh
~~~

Validacion alternativa manual (equivalente):

~~~bash
cd /opt/homelab-ubuntu-server
find docker -type f -name docker-compose.yml | sort | while read -r f; do
  echo "Validando: $f"
  docker compose -f "$f" config > /dev/null
done
~~~

## Levantamiento inicial

Orden recomendado (de base a capa de visualizacion y utilidades):

1. traefik
2. crowdsec
3. prometheus
4. loki
5. promtail
6. node-exporter
7. cadvisor
8. grafana
9. homepage
10. uptime-kuma
11. crafty

Arranque por orden recomendado:

~~~bash
cd /opt/homelab-ubuntu-server
for s in traefik crowdsec prometheus loki promtail node-exporter cadvisor grafana homepage uptime-kuma crafty; do
  echo "Levantando stack: $s"
  docker compose -f "docker/$s/docker-compose.yml" up -d
done
~~~

Comando para levantar todos los stacks de una vez:

~~~bash
cd /opt/homelab-ubuntu-server
find docker -type f -name docker-compose.yml | sort | while read -r f; do
  docker compose -f "$f" up -d
done
~~~

Verificacion rapida del estado:

~~~bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
~~~

## Carga y verificacion de cron usando scripts/crontab.homelab

Cargar cron del repo:

~~~bash
cd /opt/homelab-ubuntu-server
crontab scripts/crontab.homelab
~~~

Verificar que quedo cargado:

~~~bash
crontab -l
~~~

Verificar ejecucion y logs:

~~~bash
sudo systemctl status cron --no-pager
sudo tail -n 50 /var/log/homelab/check_docker_health.log
sudo tail -n 50 /var/log/homelab/validate_compose_all.log
~~~

## Ejecucion manual de pruebas de scripts principales

Desde /opt/homelab-ubuntu-server:

~~~bash
cd /opt/homelab-ubuntu-server

./scripts/check_docker_health.sh
./scripts/validate_compose_all.sh
./scripts/backup_configs.sh
./scripts/verify_backup_restore.sh
./scripts/rotate_prune_logs.sh
./scripts/check_tls_expiry.sh
./scripts/check_updates_report.sh
./scripts/security_baseline_audit.sh
~~~

Script de mantenimiento (requiere root):

~~~bash
cd /opt/homelab-ubuntu-server
sudo ./scripts/mantenimiento.sh
~~~

## Operacion diaria y actualizacion segura

Flujo recomendado de actualizacion (sin downtime innecesario):

~~~bash
cd /opt/homelab-ubuntu-server

# 1) Guardar configuracion antes de cambios
./scripts/backup_configs.sh

# 2) Traer cambios del repo
git pull --ff-only

# 3) Validar compose
./scripts/validate_compose_all.sh

# 4) Revisar estado actual
./scripts/check_docker_health.sh

# 5) Actualizar imagenes y recrear servicios por stack
for f in $(find docker -type f -name docker-compose.yml | sort); do
  docker compose -f "$f" pull
  docker compose -f "$f" up -d
done

# 6) Verificar nuevamente
./scripts/check_docker_health.sh
~~~

## Troubleshooting rapido

Contenedores caidos o unhealthy:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_docker_health.sh
docker ps -a --format "table {{.Names}}\t{{.Status}}"
~~~

Errores de Compose:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/validate_compose_all.sh
docker compose -f docker/grafana/docker-compose.yml config
~~~

Inspeccion de logs de un servicio:

~~~bash
docker logs --tail 200 grafana
docker logs --tail 200 traefik
~~~

Problemas de red proxy externa:

~~~bash
docker network ls | grep proxy
docker network inspect proxy
~~~

Cron no ejecuta scripts:

~~~bash
sudo systemctl status cron --no-pager
crontab -l
sudo ls -lah /var/log/homelab
~~~

## Runbooks de incidentes (L1)

### 1) Todos los contenedores caidos
- Señal: `docker ps` devuelve vacio o la mayoria de servicios aparece `Exited` en `docker ps -a`.
- Diagnostico rapido:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_docker_health.sh
docker ps -a --format "table {{.Names}}\t{{.Status}}"
sudo systemctl status docker --no-pager
~~~

- Acciones inmediatas:

~~~bash
sudo systemctl restart docker
cd /opt/homelab-ubuntu-server
for f in $(find docker -type f -name docker-compose.yml | sort); do
  docker compose -f "$f" up -d
done
~~~

- Validacion de cierre:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_docker_health.sh
docker ps --format "table {{.Names}}\t{{.Status}}"
~~~

### 2) Un stack no levanta
- Señal: un stack especifico queda en `Exit`/`Restarting` o no crea contenedores.
- Diagnostico rapido:

~~~bash
cd /opt/homelab-ubuntu-server
STACK=grafana
docker compose -f "docker/$STACK/docker-compose.yml" config
docker compose -f "docker/$STACK/docker-compose.yml" ps
docker compose -f "docker/$STACK/docker-compose.yml" logs --tail=120
~~~

- Acciones inmediatas:

~~~bash
cd /opt/homelab-ubuntu-server
STACK=grafana
docker compose -f "docker/$STACK/docker-compose.yml" pull
docker compose -f "docker/$STACK/docker-compose.yml" up -d
~~~

- Validacion de cierre:

~~~bash
cd /opt/homelab-ubuntu-server
STACK=grafana
docker compose -f "docker/$STACK/docker-compose.yml" ps
./scripts/check_docker_health.sh
~~~

### 3) Grafana sin datos
- Señal: paneles cargan, pero muestran `No data` en la mayoria de widgets.
- Diagnostico rapido:

~~~bash
curl -fsS http://localhost:3000/api/health
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:3100/ready
cd /opt/homelab-ubuntu-server
docker compose -f docker/grafana/docker-compose.yml logs --tail=120 grafana
docker compose -f docker/prometheus/docker-compose.yml logs --tail=120 prometheus
~~~

- Acciones inmediatas:

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/prometheus/docker-compose.yml up -d
docker compose -f docker/loki/docker-compose.yml up -d
docker compose -f docker/grafana/docker-compose.yml restart grafana
~~~

- Validacion de cierre:

~~~bash
curl -fsS http://localhost:3000/api/health
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:3100/ready
~~~

### 4) Loki/Promtail sin logs
- Señal: paneles de logs vacios o eventos detenidos en Security/Operations.
- Diagnostico rapido:

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/loki/docker-compose.yml ps
docker compose -f docker/promtail/docker-compose.yml ps
docker compose -f docker/loki/docker-compose.yml logs --tail=120 loki
docker compose -f docker/promtail/docker-compose.yml logs --tail=120 promtail
~~~

- Acciones inmediatas:

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/loki/docker-compose.yml restart loki
docker compose -f docker/promtail/docker-compose.yml restart promtail
docker compose -f docker/promtail/docker-compose.yml up -d
~~~

- Validacion de cierre:

~~~bash
curl -fsS http://localhost:3100/ready
cd /opt/homelab-ubuntu-server
docker compose -f docker/promtail/docker-compose.yml logs --tail=80 promtail
~~~

### 5) Disco casi lleno
- Señal: uso de disco mayor a 85% en `/` o alertas de capacidad en Grafana.
- Diagnostico rapido:

~~~bash
df -h
docker system df
sudo du -xh /var/log/homelab | sort -h | tail -n 20
~~~

- Acciones inmediatas:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/rotate_prune_logs.sh
sudo journalctl --vacuum-time=7d
docker system prune -f
~~~

- Validacion de cierre:

~~~bash
df -h
docker system df
~~~

### 6) Certificados por vencer
- Señal: alertas de TLS, errores de handshake o proximidad de expiracion (<30 dias).
- Diagnostico rapido:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_tls_expiry.sh
docker compose -f docker/traefik/docker-compose.yml logs --tail=120 traefik
~~~

- Acciones inmediatas:

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/traefik/docker-compose.yml restart traefik
./scripts/check_tls_expiry.sh
~~~

- Validacion de cierre:

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_tls_expiry.sh
docker compose -f docker/traefik/docker-compose.yml ps
~~~

## Notas de seguridad y backups

- No borres volumenes Docker ni backups sin validacion previa.
- Revisa periodicamente los hallazgos de `./scripts/security_baseline_audit.sh`.
- Mantener `PermitRootLogin no` en SSH y firewall activo (UFW o equivalente).
- Verifica expiracion de certificados con `./scripts/check_tls_expiry.sh`.
- Mantener retencion de backups y probar restore regularmente con `./scripts/verify_backup_restore.sh`.
- Para cambios de alto impacto (firewall, red, disco), aplica primero en ventana de mantenimiento.

## Inventario y ownership de servicios

| Stack | Rol | Puertos | Dependencias | Datos persistentes | Owner operativo | Criticidad (Alta/Media/Baja) | Runbook principal |
|---|---|---|---|---|---|---|---|
| traefik | Reverse proxy y punto de entrada HTTP | 80 -> 80, 8080 -> 8080 | Docker socket, red `proxy` | No aplica (sin volumen de datos propio) | Homelab Ops | Alta | L1-6 Certificados por vencer |
| crowdsec | Deteccion de amenazas y correlacion de eventos | 8081 -> 8080 | Logs del host (`/var/log`), red `proxy` | Volumen `crowdsec-data` | Homelab Ops | Media | L1-2 Un stack no levanta |
| prometheus | Recoleccion y consulta de metricas | 9090 -> 9090 | `node-exporter`, `cadvisor`, red `proxy` | `docker/prometheus/prometheus.yml` | Homelab Ops | Alta | L1-3 Grafana sin datos |
| grafana | Visualizacion de metricas y logs | 3000 -> 3000 | `prometheus`, `loki`, red `proxy` | Volumen `grafana-data`, `docker/grafana/provisioning`, `docker/grafana/dashboards` | Homelab Ops | Alta | L1-3 Grafana sin datos |
| loki | Almacenamiento y consulta de logs | 3100 -> 3100 | `promtail`, red `proxy` | Volumen `loki-data`, `docker/loki/loki-config.yml` | Homelab Ops | Media | L1-4 Loki/Promtail sin logs |
| promtail | Recoleccion y envio de logs | N/A | `loki`, logs del host (`/var/log`), red `proxy` | `docker/promtail/promtail-config.yml` | Homelab Ops | Media | L1-4 Loki/Promtail sin logs |
| node-exporter | Exportador de metricas del host | 9100 -> 9100 | Host rootfs (`/:/host`), red `proxy` | No aplica (lector del host en modo RO) | Homelab Ops | Media | L1-3 Grafana sin datos |
| cadvisor | Exportador de metricas de contenedores | 8088 -> 8080 | Docker daemon, host fs, red `proxy` | No aplica (lectura de rutas del host en modo RO) | Homelab Ops | Media | L1-3 Grafana sin datos |
| homepage | Portal de acceso a servicios del homelab | 3002 -> 3000 | Docker socket, red `proxy` | `docker/homepage/config` | Homelab Ops | Baja | L1-2 Un stack no levanta |
| uptime-kuma | Monitoreo de disponibilidad y alertas | 3001 -> 3001 | Servicios monitorizados, red `proxy` | Volumen `uptime-kuma` | Homelab Ops | Media | L1-2 Un stack no levanta |
| crafty | Panel y servicio de gestion de juego | 8443 -> 8443, 8123 -> 8123, 25565 -> 25565 | Red `proxy`, almacenamiento local del stack | `docker/crafty/crafty-config`, `docker/crafty/crafty-logs`, `docker/crafty/servers`, `docker/crafty/backups` | Homelab Ops | Baja | L1-2 Un stack no levanta |

Actualizar owner y criticidad cuando cambie el alcance del servicio.

## Rutas reales del proyecto

- Repo: /opt/homelab-ubuntu-server
- Stacks compose: /opt/homelab-ubuntu-server/docker
- Scripts operativos: /opt/homelab-ubuntu-server/scripts
- Cron file: /opt/homelab-ubuntu-server/scripts/crontab.homelab
- Logs de tareas: /var/log/homelab
- Locks de ejecucion: /var/lock/homelab
- Backups de configuracion: /var/backups/homelab/configs