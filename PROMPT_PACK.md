# Prompt Pack para la IA de desarrollo

## 0. Prompt maestro del proyecto
Eres la IA técnica principal de un producto Flutter de navegación para motociclistas. Trabaja como arquitecto senior, desarrollador Flutter/Dart, especialista Android, QA, accesibilidad y seguridad. Lee `README.md`, `PRODUCT_VISION.md`, `TECHNICAL_RESEARCH.md`, `ARCHITECTURE.md`, `MAP_ROUTING_EVALUATION.md`, `ACCESSIBILITY.md`, `TEST_STRATEGY.md` y `AI_DEVELOPMENT_RULES.md` antes de proponer cambios.

Construye una aplicación independiente. WazeTripper es solo una referencia de investigación: no lo instales, ejecutes, pruebes ni intentes conectarte a él. No modifiques el APK de Waze. No conectes la app a la moto ni al Tripper en el MVP. Usa un `NoOpExternalDisplayGateway` y simuladores. No inventes compatibilidad ni datos. Entrega código completo y pruebas, identifica incertidumbres y no afirmes que algo fue probado si no lo fue.

## 1. Prompt de arquitectura
Analiza los documentos y propón la estructura inicial del repositorio Flutter. Antes de crear código, entrega el árbol de carpetas, decisiones de estado, routing, ubicación, mapas, errores, configuración y pruebas. Mantén proveedores intercambiables y el módulo de display externo como interfaz NoOp. No añadas dependencias hasta explicar su propósito, mantenimiento, licencia y compatibilidad Android.

## 2. Prompt de evaluación de mapas
Compara proveedores actuales de tiles, geocoding y routing para una app de navegación en Colombia. Verifica tarifas y términos vigentes con fuentes oficiales. Incluye uso comercial, cuotas, cobertura rural, idioma español, atribución, caché, offline, privacidad y costo aproximado a 100/1.000/10.000 MAU. No recomiendes tiles OSM oficiales ni demo OSRM como backend comercial garantizado. Devuelve una matriz y una recomendación condicionada por costos; no integres proveedor hasta aprobación.

## 3. Prompt para crear el esqueleto Flutter
Implementa solo el esqueleto del MVP: tema, navegación de pantallas, estados loading/empty/error, modelos de dominio, interfaces de repositorios, configuración por entorno y tests. No implementes todavía un proveedor de mapas real ni BLE. El proyecto debe poder compilar con dependencias fijadas y un README con pasos reproducibles. Si no puedes ejecutar Flutter, indícalo sin afirmar éxito.

## 4. Prompt para mapa y ruta
Integra el renderer MapLibre solo después de aprobar proveedor y términos. Mantén tiles/estilo separados de geocoding y routing. Añade atribución visible, gestión de errores, límites de red, cacheado conforme a la política del proveedor y tests con respuestas mock. No incluyas descargas offline salvo que el proveedor lo permita expresamente.

## 5. Prompt para modelo neutral de navegación
Diseña entidades inmutables para ruta, tramo e instrucción. Define una enumeración de maniobras, distancia nullable, nombre de vía nullable, salida nullable, texto localizado y procedencia. Añade adaptadores de proveedor y fixtures. Si una maniobra no puede mapearse con certeza, usa `unknown`. No incluyas detección de curvas basada solo en giros de navegación.

## 6. Prompt para QA
Revisa la app contra `TEST_STRATEGY.md`. Identifica riesgos, crea pruebas unitarias/widget/integración con mocks, prueba permisos denegados, GPS ausente, conectividad intermitente, rutas vacías y textos accesibles. Verifica que el gateway externo sea NoOp y que no haya intentos BLE. Reporta pruebas realmente ejecutadas y resultados reales.

## 7. Prompt de accesibilidad y seguridad
Audita TalkBack, contraste, tamaño de fuente, etiquetas, foco, permisos, almacenamiento de ubicación, logs y acciones que puedan distraer al conductor. No recomiendes interacción manual durante conducción. Devuelve hallazgos por severidad, archivo/línea y corrección concreta.

## 8. Prompt de revisión antes de release
Haz una revisión de código para lanzamiento: dependencias y licencias, secretos, permisos Android, logs, errores de red, crash handling, atribuciones de mapas, privacidad, accesibilidad, build reproducible y pruebas. No cambies archivos hasta presentar los hallazgos y el plan de corrección.

## 9. Prompt futuro: investigación de Tripper (no ejecutar aún)
Revisa únicamente documentación y código fuente público de referencia, sin ejecutar software ni conectarte a dispositivos. Separa hechos documentados, inferencias y datos desconocidos. Evalúa si una integración externa podría implementarse de forma independiente y legal. No escribas ni habilites conexión real hasta una aprobación explícita y una revisión de seguridad/legal. No modificar hardware, firmware ni APK de Waze.
