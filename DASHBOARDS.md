# DASHBOARDS: guia operativa diaria

## 1) Titulo y objetivo
Esta guia define el uso diario de dashboards en Grafana para el homelab, sin editar consultas ni tocar expresiones de metricas/logs.

Objetivo operativo:
- Levantar y verificar el stack de observabilidad.
- Usar dashboards por perfil segun el tipo de incidencia.
- Mantener un flujo estable para dashboards fijos importados por ID.
- Validar cobertura, alertas y estado general de forma repetible.

## 2) Modo automatico recomendado
Flujo recomendado para operacion diaria (sin cambios manuales en consultas):

1. Levantar stacks requeridos:
~~~bash
cd docker/prometheus && docker compose up -d
cd ../loki && docker compose up -d
cd ../promtail && docker compose up -d
cd ../node-exporter && docker compose up -d
cd ../cadvisor && docker compose up -d
cd ../grafana && docker compose up -d
~~~

2. Reiniciar Grafana para recargar provisioning y dashboards:
~~~bash
cd docker/grafana && docker compose restart grafana
~~~

3. Verificar en la UI de Grafana (http://localhost:3000) la carpeta Homelab con estos 4 dashboards:
- Homelab Overview
- Homelab Operations
- Homelab Capacity
- Homelab Security

## 3) Dashboards por perfil
### Overview
Uso recomendado:
- Vista ejecutiva rapida del estado general.
- Confirmacion inicial de salud antes de profundizar.

### Operations
Uso recomendado:
- Incidencias activas y degradaciones recientes.
- Revision de disponibilidad de objetivos, consumo operativo y errores.

### Capacity
Uso recomendado:
- Tendencia de consumo y planeacion de capacidad.
- Identificacion de crecimiento en CPU, RAM, disco y red.

### Security
Uso recomendado:
- Seguimiento de senales de riesgo en logs y disponibilidad.
- Deteccion de patrones de fallo/autenticacion y reinicios anormales.

## 4) Dashboards fijos por ID (850/1860)
Flujo recomendado para dashboards externos fijos:

1. Importar en Grafana por ID (850 o 1860).
2. Validar visualmente que los paneles muestren datos del entorno actual.
3. Ajustar solo mapeos operativos (fuente de datos/unidades/orden), sin redisenar consultas.
4. Exportar a JSON desde la UI.
5. Guardar en docker/grafana/dashboards/.
6. Versionar cambios en el repositorio.
7. Reiniciar Grafana para confirmar carga por provisioning:
~~~bash
cd docker/grafana && docker compose restart grafana
~~~

Criterio operativo:
- No depender exclusivamente de la plantilla remota.
- Mantener copia JSON versionada para reproducibilidad y rollback.

## 5) Filtros disponibles y cuando usarlos
Filtros estandar disponibles en dashboards:
- job: separar por origen/servicio colector.
- instance: aislar host o destino especifico.
- container: focalizar analisis en un contenedor concreto.
- device: revisar comportamiento de interfaz de red o dispositivo.
- mountpoint: investigar uso de disco por punto de montaje.
- filename: acotar eventos de logs a archivo origen.

Uso recomendado:
- Empezar en contexto amplio (All) para detectar la zona afectada.
- Reducir progresivamente (job -> instance -> container/filename) para identificar causa.

## 6) Cobertura actual (senales incluidas)
Cobertura operativa actual en los dashboards del repo:
- Disponibilidad de objetivos monitoreados.
- Salud de host: CPU, memoria, disco, inodos, carga y uptime.
- Salud de contenedores: consumo de CPU/memoria y reinicios.
- Senales de red: trafico de entrada/salida por dispositivo.
- Senales de logs operativos y de error para investigacion.

## 7) No contemplado por defecto
Fuera de cobertura por defecto (requiere ampliacion posterior):
- Temperatura y telemetria avanzada de hardware.
- Latencia detallada de I/O por disco.
- Metricas de negocio o app-level especificas de cada servicio.
- Correlacion automatica de incidentes entre metricas, logs y trazas.

## 8) Alertas recomendadas (enunciadas, sin query)
Alertas de bajo ruido recomendadas para operacion:
- Host CPU alta sostenida.
- Host memoria alta sostenida.
- Uso de disco critico por punto de montaje.
- Objetivo de monitoreo caido.
- Pico de reinicios de contenedor.
- Incremento sostenido de errores en logs.

Buenas practicas:
- Definir ventanas de evaluacion para evitar ruido por picos cortos.
- Priorizar severidades por impacto al servicio (warning/critical).
- Validar cada alerta con un escenario real o controlado antes de habilitar notificaciones.

## 9) Troubleshooting operativo
1. Verificar estado de servicios:
~~~bash
cd docker/grafana && docker compose ps
cd ../prometheus && docker compose ps
cd ../loki && docker compose ps
cd ../promtail && docker compose ps
cd ../node-exporter && docker compose ps
cd ../cadvisor && docker compose ps
~~~

2. Verificar salud basica de endpoints:
~~~bash
curl -fsS http://localhost:3000/api/health
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:3100/ready
~~~

3. Verificar objetivos de Prometheus (estado de targets):
~~~bash
curl -fsS http://localhost:9090/api/v1/targets
~~~

4. Revisar logs de componentes de observabilidad:
~~~bash
cd docker/promtail && docker compose logs --tail=100 promtail
cd ../prometheus && docker compose logs --tail=100 prometheus
cd ../loki && docker compose logs --tail=100 loki
cd ../grafana && docker compose logs --tail=100 grafana
~~~

5. Si falta un dashboard provisionado, reiniciar Grafana:
~~~bash
cd docker/grafana && docker compose restart grafana
~~~

## 11) Runbooks de incidentes guiados por dashboard

### Operations: contenedor unhealthy/restarts
Accion recomendada:
1. Confirmar estado y reinicios de contenedores.

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/check_docker_health.sh
docker ps -a --format "table {{.Names}}\t{{.Status}}"
~~~

2. Revisar logs del servicio afectado para causa inmediata.

~~~bash
cd /opt/homelab-ubuntu-server
STACK=prometheus
docker compose -f "docker/$STACK/docker-compose.yml" logs --tail=120
~~~

3. Aplicar recuperacion controlada y verificar.

~~~bash
cd /opt/homelab-ubuntu-server
STACK=prometheus
docker compose -f "docker/$STACK/docker-compose.yml" up -d
docker compose -f "docker/$STACK/docker-compose.yml" ps
~~~

### Capacity: presion de CPU/RAM/disco
Accion recomendada:
1. Confirmar saturacion del host y espacio util.

~~~bash
uptime
free -h
df -h
~~~

2. Identificar presion de contenedores y consumo de Docker.

~~~bash
docker stats --no-stream
docker system df
~~~

3. Ejecutar mitigacion operativa de limpieza y volver a medir.

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/rotate_prune_logs.sh
df -h
~~~

### Security: error spikes/eventos de auth
Accion recomendada:
1. Confirmar estado de stack de seguridad y componentes base.

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/crowdsec/docker-compose.yml ps
docker compose -f docker/traefik/docker-compose.yml ps
~~~

2. Revisar eventos recientes en logs operativos.

~~~bash
cd /opt/homelab-ubuntu-server
docker compose -f docker/crowdsec/docker-compose.yml logs --tail=150 crowdsec
docker compose -f docker/traefik/docker-compose.yml logs --tail=150 traefik
~~~

3. Revalidar baseline y estado general tras accion inmediata.

~~~bash
cd /opt/homelab-ubuntu-server
./scripts/security_baseline_audit.sh
./scripts/check_docker_health.sh
~~~

## 12) Checklist final de validacion
- [ ] Grafana accesible en http://localhost:3000.
- [ ] Prometheus y Loki en estado listo.
- [ ] Los 4 dashboards de Homelab visibles y cargando datos.
- [ ] Filtros (job, instance, container, device, mountpoint, filename) con valores.
- [ ] Overview util para estado global en menos de 1 minuto.
- [ ] Operations util para diagnostico operativo sin editar paneles.
- [ ] Capacity util para detectar tendencia de consumo.
- [ ] Security util para revisar senales de riesgo y errores.
- [ ] Flujo de dashboard fijo (importar -> validar -> exportar -> versionar -> restart) probado al menos una vez.
- [ ] Sin cambios manuales de consultas durante la operacion diaria.
