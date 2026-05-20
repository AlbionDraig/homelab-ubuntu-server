# Instrucciones de Copilot para este homelab

## Objetivo
- Mantener y mejorar este homelab basado en Docker Compose con cambios pequeños, claros y reversibles.
- Priorizar estabilidad operativa, observabilidad y seguridad.

## Reglas de cambio seguro
- Hacer cambios incrementales; evitar refactors masivos sin necesidad.
- No romper nombres de servicios, volúmenes, redes ni rutas persistentes existentes.
- Conservar compatibilidad con la estructura actual del repositorio.
- Documentar brevemente el impacto de cada cambio propuesto.

## Validaciones mínimas
- Verificar sintaxis de Compose antes de aplicar cambios (`docker compose config`).
- Revisar puertos, variables de entorno y montajes para evitar conflictos.
- Confirmar que los servicios críticos siguen definidos y arrancables.
- Si hay scripts modificados, validar permisos y ejecución básica.

## Estructura esperada en `docker/`
- Un subdirectorio por servicio en `docker/<servicio>/`.
- Cada servicio debe incluir su `docker-compose.yml` y, cuando aplique, archivos de configuración locales.
- Evitar mezclar configuraciones de servicios no relacionados en una misma carpeta.

## Seguridad no destructiva
- Nunca ejecutar acciones destructivas sin confirmación explícita del usuario.
- No borrar datos persistentes, backups, volúmenes, bases de datos ni logs históricos.
- Evitar comandos peligrosos (por ejemplo, recreaciones forzadas con pérdida de datos) sin aviso claro.
- Proponer primero alternativas seguras y reversibles.

## Estilo de respuesta
- Responder en español, de forma concisa y orientada a operaciones.
- Explicar qué cambió, por qué y cómo validar rápidamente.
- Incluir rutas de archivos y comandos concretos cuando aplique.
- Señalar riesgos, supuestos y próximos pasos opcionales.
