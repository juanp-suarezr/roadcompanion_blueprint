# Road companion — blueprint técnico inicial

Estado: **documentación de descubrimiento**, no implementación validada en hardware.

## Objetivo
Diseñar una aplicación móvil independiente en Flutter para navegación de motociclistas, con mapas/rutas y una integración opcional con el Royal Enfield Tripper Pod original únicamente si el protocolo y la compatibilidad se pueden validar de forma segura.

## Restricciones no negociables
- No instalar, ejecutar, probar ni intentar conectarse a WazeTripper.
- WazeTripper se estudia solo como referencia documental/código.
- No modificar el APK de Waze ni integrar código propietario de Waze.
- No intervenir físicamente la moto, cableado, ECU, firmware o Tripper.
- No afirmar compatibilidad con el Tripper hasta validarla de forma controlada y segura.
- El teléfono de referencia es Samsung Galaxy A35, Android 16; esto no demuestra compatibilidad BLE con el Tripper.
- No usar servidores públicos de mapas/rutas como backend comercial garantizado.
- Cualquier uso del protocolo no oficial debe someterse a revisión legal, técnica y de seguridad.

## Documentos
1. `PRODUCT_VISION.md` — producto y alcance.
2. `TECHNICAL_RESEARCH.md` — hallazgos, evidencia y límites de certeza sobre WazeTripper.
3. `ARCHITECTURE.md` — arquitectura propuesta.
4. `MAP_ROUTING_EVALUATION.md` — mapa, geocodificación y routing.
5. `ACCESSIBILITY.md` — accesibilidad y seguridad de uso.
6. `TEST_STRATEGY.md` — estrategia de calidad.
7. `AI_DEVELOPMENT_RULES.md` — instrucciones para IA de desarrollo.
8. `PROMPT_PACK.md` — prompts por rol y tareas.

## Estado recomendado del MVP
**MVP-1 sin Tripper:** app Flutter con mapa, búsqueda de destino, cálculo de ruta mediante proveedor sustituible, resumen de navegación y simulación de instrucciones con datos ficticios. Así se valida UX y arquitectura sin conectarse al hardware.

**MVP-2 integración experimental:** solo tras revisión del protocolo, permisos, compatibilidad legal y plan de pruebas; conexión BLE no debe habilitarse por defecto en builds normales.

## Fuentes iniciales
- WazeTripper: https://github.com/jnsdias/wazetripper
- Protocolo documentado: https://github.com/jnsdias/wazetripper/blob/main/docs/PROTOCOL.md
- Guía de desarrollo: https://github.com/jnsdias/wazetripper/blob/main/docs/DEVELOPMENT.md
- Changelog: https://github.com/jnsdias/wazetripper/blob/main/CHANGELOG.md
- MapLibre Flutter: https://github.com/maplibre/flutter-maplibre-gl
- Política de tiles OSM: https://operations.osmfoundation.org/policies/tiles/
- Política de tiles vectoriales OSM: https://operations.osmfoundation.org/policies/vector/
- Política/advertencias del demo OSRM: https://github.com/Project-OSRM/osrm-backend/wiki/Api-usage-policy

Las condiciones de los proveedores cambian: volver a verificar licencias, cuotas y precios antes de publicar o monetizar.
