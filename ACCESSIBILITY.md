# Accessibility & Riding Safety

## 1. Objetivo
La app debe ser usable por personas con distintas capacidades, pero también reducir la necesidad de mirar o tocar el teléfono al conducir. Accesibilidad no significa que todas las acciones deban estar disponibles mientras la moto se mueve.

## 2. Requisitos UI
- Contraste legible en sol y en modo oscuro; no depender solo del color.
- Tipografía escalable y soporte de tamaño de fuente del sistema.
- Semántica y etiquetas accesibles para TalkBack.
- Objetivos táctiles generosos para uso estacionado.
- Estados de carga/error expresados con texto, no solo animaciones.
- Orden de foco lógico y navegación compatible con teclado cuando corresponda.
- Preferencias de movimiento reducido cuando existan animaciones.
- Localización inicial en español; no concatenar cadenas que impidan traducir.
- Iconos de maniobra acompañados por texto accesible en el teléfono.

## 3. Seguridad vial
- No exigir mirar el mapa para entender una maniobra.
- Evitar alertas visuales o sonoras innecesarias.
- No permitir introducir destinos o editar ajustes complejos durante navegación activa.
- Mostrar una indicación de detenerse en un lugar seguro para acciones que requieran atención.
- No afirmar que la aplicación elimina distracciones ni reemplaza señales viales.
- El volumen, audio Bluetooth y notificaciones deben configurarse y probarse en condiciones estacionarias.
- Las alertas de curvas solo se agregarán con datos verificados y umbrales revisados; no inferir peligro a partir de una simple maniobra de giro.

## 4. Ubicación y permisos
- Pedir ubicación en primer plano solo cuando el usuario use funciones que la necesitan.
- Explicar el valor de cada permiso antes del diálogo del sistema.
- Si se deniega, permitir explorar el mapa o introducir origen/destino manualmente cuando sea viable.
- No pedir ubicación en segundo plano en el MVP.
- Diferenciar GPS apagado, permiso denegado y señal imprecisa.

## 5. Validación
- Android TalkBack.
- Tamaño de fuente al 200%.
- Contraste y modo oscuro.
- Pruebas en exterior con brillo alto, con la moto estacionada.
- Pruebas de flujo con una mano cuando sea seguro y sin simular interacción mientras se conduce.
