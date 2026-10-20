# Product Vision

## 1. Problema
Los motociclistas quieren recibir indicaciones útiles sin depender de una pantalla grande ni distraerse mirando el teléfono. El Tripper Pod es un display de indicaciones compacto, pero la integración de terceros no está oficialmente documentada.

## 2. Visión
Crear un copiloto de navegación para motociclistas, independiente de marcas y motos, con una experiencia clara, accesible y modular. La integración con un display externo es una capacidad opcional, no un requisito para que la aplicación aporte valor.

## 3. Usuarios iniciales
- Motociclistas que hacen trayectos urbanos y viajes por carretera.
- Usuarios Android que necesitan navegación simple y legible.
- En una etapa posterior: comunidades moteras y fabricantes/instaladores de accesorios compatibles.

## 4. Propuesta de valor
- Planear y visualizar rutas.
- Mostrar próximas maniobras, distancia y progreso.
- Mantener una interfaz de baja distracción.
- Soportar distintos proveedores de mapas/rutas mediante interfaces.
- Integración con dispositivos externos solo cuando exista compatibilidad validada.

## 5. MVP
Incluye:
- Flutter + Dart para Android.
- Pantalla principal de mapa.
- Selección de origen/destino y vista de ruta.
- Resumen de distancia/tiempo si el proveedor lo ofrece.
- Navegación simulada con fixtures de prueba.
- Estados claros: sin permiso, sin GPS, sin conexión, error de ruta.
- Preferencias básicas y privacidad.
- Atribución/licencias visibles.
- Registro técnico sin almacenar rutas personales por defecto.

No incluye inicialmente:
- Reemplazar Google Maps/Waze en cobertura, tráfico o calidad.
- Prometer navegación offline.
- Alertas de curvas en tiempo real sin datos confiables.
- Control de la motocicleta, ECU, sensores o firmware.
- Conexión real al Tripper en el MVP inicial.
- Funciones que requieran modificar el APK de otra app.

## 6. Métricas de éxito
- La persona puede elegir un destino y visualizar una ruta sin errores.
- Errores de permisos/GPS explicados en lenguaje claro.
- La app no se bloquea al perder temporalmente red o ubicación.
- Pruebas automatizadas de lógica crítica.
- Accesibilidad validada con TalkBack y escalado de texto.
- Costos por usuario conocidos antes de cualquier lanzamiento público.

## 7. Seguridad de conducción
La app no debe fomentar interacción manual mientras la moto está en movimiento. Las acciones complejas deben hacerse antes de salir o cuando el usuario se detenga. La app es un apoyo, no reemplaza señales, juicio del conductor ni navegación oficial del vehículo.

## 8. Riesgos
- Protocolo Tripper no oficial, incompleto o sujeto a cambios.
- Compatibilidad BLE no demostrada en Galaxy A35.
- Costos/condiciones de mapas y routing.
- Cobertura de mapas variable en zonas rurales de Colombia.
- Riesgo de distracción, consumo de batería y pérdida de señal.
- Consideraciones legales, marcas registradas y licencias.
