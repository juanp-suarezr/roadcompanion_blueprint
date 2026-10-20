# Technical Research: WazeTripper como referencia

## 1. Alcance y límites
Esta investigación usa el repositorio público como material de lectura. No se instala, ejecuta, prueba ni conecta WazeTripper con ningún dispositivo. Ninguna conclusión equivale a una prueba física en una Meteor 350 o un Galaxy A35.

Repositorio: https://github.com/jnsdias/wazetripper

## 2. Qué es
Según el README y documentación del proyecto, WazeTripper es un proyecto de ingeniería inversa comunitario para mostrar indicaciones de navegación de Waze en el pequeño Tripper Pod de Royal Enfield. No es el Tripper Dash de pantalla más grande.

El proyecto documenta un flujo que obtiene datos de navegación mediante una modificación de la aplicación Android de Waze y luego transmite indicaciones al Tripper. Por eso no es la arquitectura que adoptará este producto: nuestro objetivo es una app independiente y no modificar el APK de Waze.

## 3. Elementos documentados en el repositorio
- Nombre BLE observado/documentado: `RE_DISP`.
- UUID de servicio documentado: `01FF0100-BA5E-F4EE-5CA1-EB1E5E4B1CE0`.
- UUID de característica documentado: `01FF0101-BA5E-F4EE-5CA1-EB1E5E4B1CE0`.
- Paquetes descritos como tramas de 20 bytes: 18 bytes de carga útil y 2 bytes de CRC.
- CRC descrito como CRC-16/CCITT-FALSE: polinomio `0x1021`, inicial `0xFFFF`, procesamiento MSB-first, sin XOR final y CRC en orden big-endian.
- La documentación describe intercambio BLE, handshake/PIN, keepalive, reconexión y refresco de pantalla.
- El código se divide, entre otros, en componentes equivalentes a protocolo, puente BLE, panel de ajustes y overlay de Waze.
- La documentación menciona una cadencia de refresco/keepalive de aproximadamente dos segundos y un watchdog de pantalla de unos pocos segundos. Tratar los tiempos como observaciones del proyecto, no como especificación oficial de Royal Enfield.
- La documentación incluye códigos/iconos de maniobras. Una maniobra de navegación no equivale a detectar de forma fiable cada curva natural de la carretera.

## 4. Lo que NO se puede concluir
- No se ha confirmado que el Galaxy A35 con Android 16 pueda conectarse correctamente al Tripper.
- No se ha confirmado compatibilidad con todas las versiones de firmware o motos.
- No existe garantía de estabilidad, seguridad o soporte oficial de Royal Enfield.
- No se debe afirmar que el protocolo sea completo, estable o autorizado.
- No se debe asumir que los datos de navegación de cualquier proveedor puedan transformarse directamente en mensajes válidos sin una capa de adaptación y validación.
- No se debe inferir que el código/documentación permiten legalmente cualquier tipo de reutilización de marcas, APK o datos de terceros.

## 5. Licencias y límites de reutilización
El repositorio declara una licencia para el código del proyecto; revisar el archivo LICENSE y cada dependencia antes de reutilizar cualquier fragmento. Esa licencia no concede derechos sobre Waze, Royal Enfield, sus marcas, sus APK ni otros materiales de terceros. La aplicación propuesta debe preferir una implementación propia basada en especificaciones documentadas y evitar redistribuir componentes de terceros no autorizados.

## 6. Evaluación de riesgo
| Tema | Riesgo | Tratamiento |
|---|---|---|
| BLE/handshake | Alto: protocolo no oficial | Aislar en módulo; no habilitar en MVP |
| Compatibilidad A35 | Desconocida | No prometer; diseñar matriz de validación posterior |
| Watchdog/keepalive | Medio-alto | Documentar, probar solo con autorización y entorno controlado |
| CRC y paquetes | Medio | Crear pruebas unitarias basadas en vectores documentados, sin conexión física |
| Indicaciones de navegación | Medio | Definir contrato neutral de maniobras y adaptadores |
| Curvas/alertas | Alto si no hay datos fiables | Excluir de MVP; no inferir curvas solo por giros de navegación |
| Marcas y APK de Waze | Alto | No parchear ni redistribuir Waze |

## 7. Recomendación
La investigación de WazeTripper sirve para entender el problema de integración, no para convertir su arquitectura en la base del producto. Construir primero una app útil sin conexión al Tripper; después decidir si una integración experimental es viable, legal y suficientemente segura.
