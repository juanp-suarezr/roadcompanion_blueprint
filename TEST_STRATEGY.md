# Test Strategy

## 1. Regla de seguridad
En la etapa inicial, todas las pruebas de integración con display externo deben ser simuladas. No instalar, ejecutar ni conectarse a WazeTripper. No realizar pruebas BLE reales con la moto o Tripper en esta fase.

## 2. Pirámide de pruebas
### Unitarias
- conversión de DTOs de rutas a modelo neutral;
- adaptación de maniobras;
- cálculo/formatos de distancia;
- validación de coordenadas;
- manejo de errores;
- selección de proveedor;
- persistencia de preferencias;
- lógica de estado de navegación.

### Widget tests
- pantalla vacía, cargando, éxito y error;
- permiso denegado;
- búsqueda sin resultados;
- ruta encontrada/no encontrada;
- textos largos y escalado de fuente;
- semántica accesible.

### Integración (MVP)
- destino → geocoding mock → routing mock → pantalla de ruta;
- pérdida/restauración de conectividad;
- ubicación deshabilitada;
- cierre/reapertura de app;
- cambio de proveedor por configuración de test;
- gateway externo NoOp nunca intenta conexión.

### Manuales en dispositivo
- Galaxy A35 / Android 16 para UI, permisos, GPS, consumo de batería y ciclo de vida.
- No validar BLE/Tripper hasta una fase aprobada y separada.

## 3. Contratos y fixtures
Usar fixtures versionados con rutas ficticias y maniobras conocidas. No guardar ubicaciones personales reales en repositorio. Simular reloj y progresión de navegación; evitar `sleep` largos en tests.

## 4. Calidad
- `dart format` y `flutter analyze` sin errores.
- Cobertura alta en lógica de dominio crítica; no perseguir porcentaje artificial en widgets triviales.
- Dependencias con licencia revisada y mantenimiento activo.
- CI con tests, análisis estático y builds reproducibles.
- Dependabot/Renovate o proceso equivalente con revisión manual.
- Threat modeling básico antes de cualquier integración externa.
- Checklist de release: privacidad, permisos, atribuciones, logs, claves, crash handling.

## 5. Criterios de aceptación MVP
- Puede abrir mapa y mostrar atribución.
- Puede buscar/seleccionar destino con proveedor configurado.
- Puede mostrar ruta o error recuperable.
- No se bloquea si falta GPS o red.
- Ninguna conexión BLE se inicia.
- No registra coordenadas en logs.
- TalkBack identifica controles principales.
- Tests automatizados pasan en CI.
