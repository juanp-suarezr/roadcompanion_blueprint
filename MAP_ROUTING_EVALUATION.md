# Map & Routing Evaluation

## 1. Separar cuatro servicios
1. **Renderizado:** dibujar el mapa en pantalla.
2. **Tiles/estilos:** servir datos visuales del mapa.
3. **Geocodificación:** convertir una dirección/lugar en coordenadas.
4. **Routing:** calcular ruta, geometría, duración e instrucciones.
Un SDK de mapa no necesariamente ofrece los otros tres servicios.

## 2. Opción base a evaluar
**MapLibre Flutter + proveedor de tiles compatible + proveedor de geocoding/routing separado.**

MapLibre es un renderizador; no garantiza por sí solo navegación paso a paso ni datos de tráfico. Mantener interfaces separadas permite cambiar proveedor sin reescribir la aplicación.

Documentación de inicio: https://github.com/maplibre/flutter-maplibre-gl

## 3. Comparación de enfoques
| Opción | Ventajas | Límites/riesgos | Uso recomendado |
|---|---|---|---|
| MapLibre + tiles de un proveedor comercial con free tier | Flexibilidad, control de estilo, coste inicial bajo | Límites de cuota, atribución, posible coste al crecer | Candidato principal para MVP tras verificar términos |
| Google Maps Platform | Ecosistema conocido, datos/servicios integrados | Cobro, cuotas y condiciones de uso; dependencia del proveedor | Evaluar si calidad de direcciones/rutas justifica coste |
| Mapbox u otro proveedor OSM comercial | Herramientas integradas y posible soporte de navegación | Tarifas y restricciones cambian; revisar SDK, offline y uso comercial | Comparación de precio/rendimiento antes del lanzamiento |
| Tiles OSM oficiales `tile.openstreetmap.org` | Fáciles para prototipos con uso interactivo moderado | Sin SLA, atribución obligatoria, no permite predescarga/offline, posible bloqueo por uso indebido | No usar como backend comercial garantizado |
| Demo público OSRM | Útil para experimentar con routing | Sin SLA; disponibilidad y uso comercial pueden restringirse | No depender de él en producción |
| Autoalojar tiles/routing | Mayor control y potencial de costos previsibles a escala | Operación, actualización de datos, infraestructura y monitoreo propios | Considerar cuando haya demanda real y capacidad operativa |

## 4. Política OSM: puntos obligatorios
La política oficial establece que los datos de OpenStreetMap son abiertos, pero los servidores públicos de tiles no son un servicio ilimitado gratuito. Entre otros requisitos: atribución visible, identificación apropiada de la aplicación, respeto de caché y no hacer descargas masivas ni preparar mapas offline desde el servidor estándar.
Fuente: https://operations.osmfoundation.org/policies/tiles/
Política de tiles vectoriales: https://operations.osmfoundation.org/policies/vector/

## 5. Routing y geocoding
- No usar el servidor demo de OSRM como dependencia de producción ni prometer SLA.
- No asumir que un proveedor gratuito permite uso comercial, navegación turno a turno o almacenamiento de resultados.
- Antes de elegir, verificar: cobertura de Colombia y vías rurales, instrucciones en español, límites por minuto/mes, atribución, almacenamiento/caché, uso comercial, privacidad, soporte de motocicleta y términos de navegación.
- Las restricciones de ruta por tipo de vehículo no siempre modelan bien una motocicleta en Colombia. Validar el comportamiento y permitir al usuario revisar la ruta.
- Tráfico en tiempo real no debe prometerse si el proveedor no lo entrega.

## 6. Decisión recomendada
Para prototipo: MapLibre como renderer y un proveedor de rutas/geocoding seleccionado después de revisar sus condiciones vigentes. Mantener proveedores detrás de interfaces. Usar OSM oficial solo respetando su política y sin tratarlo como un servicio comercial garantizado.

## 7. Checklist antes de elegir proveedor
- [ ] Tarifas actuales y umbrales del free tier.
- [ ] Uso comercial permitido.
- [ ] Uso de la API desde móvil permitido.
- [ ] Restricción/gestión de API keys.
- [ ] Cobertura Pereira–Armenia, rutas rurales y carreteras secundarias.
- [ ] Instrucciones de maniobra y nombres de vías en español.
- [ ] Política de caché, almacenamiento y offline.
- [ ] Atribución visible.
- [ ] SLA y límites de tasa.
- [ ] Política de privacidad y retención.
- [ ] Coste estimado a 100, 1.000 y 10.000 usuarios activos mensuales.
