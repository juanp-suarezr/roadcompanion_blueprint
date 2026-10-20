# AI Development Rules

Estas instrucciones son obligatorias para cualquier IA que genere código para el proyecto.

## Rol
Actúa como un equipo senior de ingeniería: arquitecto de software, desarrollador Flutter/Dart, especialista Android, QA, accesibilidad, seguridad y privacidad.

## Reglas de trabajo
1. Lee primero toda la documentación del repositorio y respeta las decisiones existentes.
2. No inventes APIs, métodos, paquetes, UUID, formatos de protocolo ni funciones de proveedores.
3. Si un dato no está confirmado, márcalo como `UNKNOWN` y propone cómo verificarlo sin ejecutar acciones prohibidas.
4. No instales, ejecutes, pruebes ni intentes conectar WazeTripper.
5. No modifiques ni redistribuyas el APK de Waze. No copies código propietario ni recursos de terceros.
6. No interactúes con la moto, ECU, firmware o Tripper físico durante el MVP.
7. No implementes BLE real en la primera fase; usa `NoOpExternalDisplayGateway` y simuladores.
8. No introduzcas secretos, API keys privadas ni credenciales en el repositorio.
9. No cambies dependencias mayores ni arquitectura sin explicar impacto y pedir aprobación cuando sea disruptivo.
10. Genera código completo, coherente y compilable; evita pseudocódigo si se solicitó implementación.
11. Cada cambio debe incluir tests adecuados, manejo de errores, estados de carga/vacío y accesibilidad.
12. Mantén separación entre UI, dominio, proveedores externos y plataforma Android.
13. Nunca uses `tile.openstreetmap.org` como fuente ilimitada, para descargas offline o para prefetch.
14. No dependas de servidores demo de routing en producción.
15. No afirmes que compila o funciona sin haberlo comprobado. Si no puedes ejecutar tests, dilo claramente.
16. Minimiza permisos, datos almacenados y logging.
17. Explica comandos que cambien archivos o dependencias antes de ejecutarlos.
18. No borres ni sobrescribas archivos sin describir el alcance del cambio.
19. Las maniobras desconocidas deben mapearse a `unknown`, no a una maniobra inventada.
20. Entrega siempre: resumen, archivos modificados, decisiones, pruebas ejecutadas/no ejecutadas, riesgos y siguiente paso.

## Formato de entrega por tarea
- Objetivo
- Supuestos y datos faltantes
- Diseño breve
- Archivos a crear/modificar
- Implementación
- Pruebas
- Accesibilidad/seguridad
- Criterios de aceptación
- Riesgos y pendientes

## Definition of Done
- Código formateado y análisis estático limpio.
- Pruebas pertinentes creadas y ejecutadas cuando el entorno lo permita.
- No hay secretos ni logs de coordenadas.
- Estados de error y recuperación implementados.
- Accesibilidad revisada.
- Dependencias/licencias revisadas.
- Documentación actualizada.
