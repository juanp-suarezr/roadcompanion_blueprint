# Architecture

## 1. Principios
- Feature-first en la capa de presentación y separación por dominio.
- Dependencias hacia abstracciones, no hacia proveedores concretos.
- Tipos inmutables para rutas y maniobras.
- Estado explícito y errores tipados.
- Sin secretos ni claves privadas embebidas en el cliente.
- BLE aislado detrás de una interfaz y deshabilitado en el MVP.
- Telemetría mínima y opt-in; no registrar coordenadas por defecto.

## 2. Stack propuesto
- Flutter / Dart stable, versiones fijadas en el proyecto.
- Riverpod o Bloc: elegir uno y usarlo consistentemente; recomendación inicial: Riverpod si el equipo domina su modelo.
- go_router para navegación interna si el número de pantallas lo justifica.
- Dio o cliente HTTP equivalente detrás de repositorios.
- Geolocator (o alternativa mantenida) para ubicación, sujeto a permisos Android y pruebas de ciclo de vida.
- MapLibre Flutter para renderizar mapas, con proveedor de tiles explícito.
- Persistencia local simple (shared preferences para preferencias no sensibles; base local para favoritos/historial si se añade).
- Kotlin nativo mediante Platform Channels solo si una función Android concreta no queda cubierta por un paquete Flutter mantenido y auditado.

No fijar versiones de dependencias sin comprobar sus releases, compatibilidad Android, licencia y actividad de mantenimiento al iniciar el repositorio.

## 3. Capas
`presentation/` — pantallas, widgets accesibles, controladores/estado.
`domain/` — entidades y casos de uso sin dependencias de Flutter.
`data/` — repositorios, DTOs, mapeadores, clientes HTTP.
`platform/` — ubicación y adaptadores nativos.
`navigation/` — proveedor de rutas, normalización de maniobras y simulación.
`maps/` — renderer y proveedor de tiles.
`tripper/` — interfaz abstracta y, solo en una fase posterior, implementación BLE experimental.
`core/` — errores, configuración, logging redactado, resultado/estado.

## 4. Interfaces de dominio sugeridas
- `MapStyleProvider`: entrega configuración/URL de estilo y atribución.
- `GeocodingRepository`: busca destinos.
- `RoutingRepository`: calcula una ruta y devuelve geometría, distancia, duración e instrucciones disponibles.
- `LocationRepository`: expone posición/precisión/estado de permisos.
- `NavigationSession`: estado de navegación actual y próxima maniobra.
- `ManeuverAdapter`: transforma instrucciones del proveedor a un modelo neutral.
- `ExternalDisplayGateway`: contrato opcional para enviar una instrucción resumida a un display; la implementación inicial será `NoOpExternalDisplayGateway`.
- `SettingsRepository`: preferencias del usuario.

## 5. Modelo neutral de maniobra
Campos conceptuales:
- `type`: straight, slight_left, left, sharp_left, slight_right, right, sharp_right, u_turn, roundabout, arrive, depart, unknown.
- `distanceMeters`: nullable, no inventar si el proveedor no la entrega.
- `roadName`: nullable.
- `exitNumber`: nullable.
- `instructionText`: texto localizado.
- `confidence/source`: para distinguir dato del proveedor de una inferencia.
No representar una curva de carretera como maniobra si no proviene de datos confiables.

## 6. Flujo de datos
1. Usuario elige destino.
2. Geocoding busca opciones.
3. Routing calcula la ruta mediante el proveedor seleccionado.
4. El adaptador convierte instrucciones a entidades neutrales.
5. La UI presenta ruta y resumen.
6. En modo simulación, un reloj de prueba o fixtures avanzan maniobras; no usar temporizadores reales en tests frágiles.
7. Un gateway externo `NoOp` ignora cualquier envío a dispositivos en el MVP.

## 7. Gestión de errores
Errores diferenciados:
- permiso de ubicación denegado / permanentemente denegado;
- ubicación no disponible o baja precisión;
- sin conectividad;
- proveedor agotó cuota;
- ruta no encontrada;
- respuesta inválida;
- mapa no cargado;
- servicio no disponible.
Mostrar recuperación concreta y no perder destino si la ruta falla.

## 8. Seguridad y privacidad
- Solicitar permisos cuando se necesiten, explicar por qué.
- No pedir ubicación en segundo plano en MVP.
- Evitar ubicación precisa persistente por defecto.
- No registrar coordenadas, tokens, identificadores BLE ni datos personales en logs.
- Guardar claves de proveedor en backend cuando el proveedor lo requiera; las restricciones de clave de cliente no sustituyen cuotas/monitorización.
- Deshabilitar endpoints de debug y logging verboso en builds release.
- No realizar conexión BLE automática en el MVP.

## 9. Estrategia de escalabilidad
- Proveedor de mapas/rutas intercambiable.
- Configuración por entorno.
- Contratos de dominio testeables sin Android ni red.
- Backend futuro solo si aporta valor (cuentas, sincronización, proxy seguro, analítica opt-in, gestión de cuotas).
- No crear microservicios antes de necesitarlos; empezar como app modular.
