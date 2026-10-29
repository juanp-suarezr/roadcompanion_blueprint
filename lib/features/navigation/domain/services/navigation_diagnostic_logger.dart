import 'package:flutter/foundation.dart';

import '../../../../domain/entities/coordinates.dart';
import '../entities/calculated_route.dart';
import '../entities/destination.dart';

/// Niveles obligatorios de trazabilidad de extremo a extremo (Sección 11).
enum DiagnosticPipelineStage {
  /// 1. Evento crudo recibido por el sistema Android (NotificationListener / Sensor GPS).
  l1AndroidEvent('L1:ANDROID_EVENT', '1. Evento recibido por Android'),

  /// 2. Evento interpretado por el parser o adaptador de RoadCompanion.
  l2ParsedEvent('L2:PARSED_EVENT', '2. Evento interpretado por RoadCompanion'),

  /// 3. Instrucción convertida al modelo interno de maniobra / curvatura.
  l3InternalModel(
    'L3:INTERNAL_MODEL',
    '3. Instrucción convertida al modelo interno',
  ),

  /// 4. Trama de 20 bytes escrita efectivamente al transporte BLE (RE_DISP).
  l4BleTx('L4:BLE_TX', '4. Paquete escrito a BLE'),

  /// 5. Resultado visual observado físicamente en el Tripper Pod (requiere validación física).
  l5PhysicalObservation(
    'L5:PHYSICAL_OBS',
    '5. Resultado visual observado físicamente',
  );

  final String tag;
  final String description;
  const DiagnosticPipelineStage(this.tag, this.description);
}

/// Entrada estructurada e inmutable del registro de observabilidad en 5 niveles.
class DiagnosticPipelineEntry {
  final DiagnosticPipelineStage stage;
  final String source;
  final String summary;
  final DateTime timestamp;

  const DiagnosticPipelineEntry({
    required this.stage,
    required this.source,
    required this.summary,
    required this.timestamp,
  });

  String format() {
    final ts = timestamp.toIso8601String().substring(11, 19);
    return '[$ts][${stage.tag}][$source] $summary';
  }
}

/// Servicio centralizado de diagnóstico para búsqueda geográfica, cálculo de rutas
/// y observabilidad en 5 niveles de sincronización con el Tripper Pod.
///
/// Permite auditar el comportamiento del sistema respetando la privacidad del usuario
/// sin almacenar contenido privado completo ni exponer credenciales.
class NavigationDiagnosticLogger {
  NavigationDiagnosticLogger._();

  static bool isEnabled = true;
  static const int _maxPipelineEntries = 200;
  static final List<DiagnosticPipelineEntry> _pipelineEntries = [];

  /// Devuelve las entradas registradas, opcionalmente filtradas por nivel.
  static List<DiagnosticPipelineEntry> getPipelineEntries({
    DiagnosticPipelineStage? filterStage,
  }) {
    if (filterStage == null) {
      return List.unmodifiable(_pipelineEntries);
    }
    return List.unmodifiable(
      _pipelineEntries.where((e) => e.stage == filterStage),
    );
  }

  /// Limpia las entradas de observabilidad en memoria.
  static void clearPipelineEntries() {
    _pipelineEntries.clear();
  }

  /// Registra un evento en uno de los 5 niveles del pipeline de navegación/BLE,
  /// redactando cadenas excesivamente largas para proteger la privacidad.
  static void logPipeline({
    required DiagnosticPipelineStage stage,
    required String source,
    required String summary,
    DateTime? timestamp,
  }) {
    if (!isEnabled) return;
    final redacted = summary.length > 140
        ? '${summary.substring(0, 140)}…'
        : summary;
    final entry = DiagnosticPipelineEntry(
      stage: stage,
      source: source,
      summary: redacted,
      timestamp: timestamp ?? DateTime.now(),
    );
    _pipelineEntries.insert(0, entry);
    if (_pipelineEntries.length > _maxPipelineEntries) {
      _pipelineEntries.removeRange(
        _maxPipelineEntries,
        _pipelineEntries.length,
      );
    }
    debugPrint('[REstelar:Pipeline] ${entry.format()}');
  }

  /// Registra el inicio de una búsqueda geográfica (por categoría o por destino concreto).
  static void logSearchStart({
    required String originalQuery,
    required String normalizedQuery,
    required bool isCategory,
    required Coordinates? userLocation,
    required String provider,
    required Map<String, String> parameters,
  }) {
    if (!isEnabled) return;
    final locationDesc = userLocation != null
        ? 'GPS(${userLocation.latitude.toStringAsFixed(4)}, ${userLocation.longitude.toStringAsFixed(4)})'
        : 'Sin GPS (ubicación no disponible)';

    debugPrint(
      '[REstelar:Diagnostic:Search] INICIO BÚSQUEDA\n'
      '  - Consulta original: "$originalQuery"\n'
      '  - Consulta normalizada: "$normalizedQuery"\n'
      '  - Tipo de búsqueda: ${isCategory ? "Categoría local cercana" : "Destino específico / topónimo"}\n'
      '  - Ubicación base: $locationDesc\n'
      '  - Proveedor: $provider\n'
      '  - Parámetros: $parameters',
    );
  }

  /// Registra el resultado obtenido del proveedor de geocodificación.
  static void logSearchResults({
    required String query,
    required int rawResultsCount,
    required List<Destination> results,
    required Coordinates? userLocation,
  }) {
    if (!isEnabled) return;
    final buffer = StringBuffer(
      '[REstelar:Diagnostic:Search] RESULTADOS RECIBIDOS (${results.length} destinos)\n',
    );
    for (int i = 0; i < results.length; i++) {
      final d = results[i];
      final distStr = userLocation != null
          ? ' - ${(userLocation.distanceTo(d.coordinates) / 1000.0).toStringAsFixed(2)} km'
          : '';
      buffer.writeln(
        '  [$i] "${d.title}" (${d.subtitle}) @ (${d.coordinates.latitude.toStringAsFixed(5)}, ${d.coordinates.longitude.toStringAsFixed(5)})$distStr [id=${d.id}, cat=${d.category ?? "n/a"}]',
      );
    }
    debugPrint(buffer.toString());
  }

  /// Registra la selección de un destino y sus coordenadas exactas antes de rutear.
  static void logDestinationSelected({
    required Destination destination,
    required Coordinates? origin,
  }) {
    if (!isEnabled) return;
    final originDesc = origin != null
        ? '(${origin.latitude.toStringAsFixed(5)}, ${origin.longitude.toStringAsFixed(5)})'
        : 'Desconocido';
    debugPrint(
      '[REstelar:Diagnostic:Selection] DESTINO SELECCIONADO\n'
      '  - Título: "${destination.title}"\n'
      '  - Subtítulo: "${destination.subtitle}"\n'
      '  - Coordenadas exactas destino: (${destination.coordinates.latitude.toStringAsFixed(6)}, ${destination.coordinates.longitude.toStringAsFixed(6)})\n'
      '  - Origen de ruta: $originDesc\n'
      '  - ID OSM: ${destination.id}',
    );
  }

  /// Registra el resultado del cálculo de rutas con OSRM y la auditoría de alternativas.
  static void logRoutingDiagnostics({
    required Coordinates origin,
    required Coordinates destination,
    required String requestUri,
    required int rawRoutesCount,
    required int validatedRoutesCount,
    required List<CalculatedRoute> validatedRoutes,
    required List<String> discardReasons,
    Coordinates? problemCoordinateDetected,
    String? restrictionSegmentAndEvidence,
    String? publicAlternativeSelected,
    String? finalResultPresented,
  }) {
    if (!isEnabled) return;
    final buffer = StringBuffer(
      '[REstelar:Diagnostic:Routing] AUDITORÍA DE RUTAS OSRM\n'
      '  - Origen: (${origin.latitude.toStringAsFixed(6)}, ${origin.longitude.toStringAsFixed(6)})\n'
      '  - Destino: (${destination.latitude.toStringAsFixed(6)}, ${destination.longitude.toStringAsFixed(6)})\n'
      '  - Petición URI: $requestUri\n'
      '  - Cantidad devuelta por OSRM (antes de validar): $rawRoutesCount\n'
      '  - Cantidad tras validación de restricciones: $validatedRoutesCount\n',
    );

    if (problemCoordinateDetected != null) {
      buffer.writeln(
        '  - Coordenada problemática detectada: (${problemCoordinateDetected.latitude.toStringAsFixed(6)}, ${problemCoordinateDetected.longitude.toStringAsFixed(6)})',
      );
    }

    if (restrictionSegmentAndEvidence != null) {
      buffer.writeln(
        '  - Segmento restrictivo y evidencia: $restrictionSegmentAndEvidence',
      );
    }

    if (publicAlternativeSelected != null) {
      buffer.writeln(
        '  - Acceso público alternativo seleccionado: $publicAlternativeSelected',
      );
    }

    if (discardReasons.isNotEmpty) {
      buffer.writeln('  - Motivos de descarte o relegación:');
      for (final reason in discardReasons) {
        buffer.writeln('     * $reason');
      }
    }

    if (rawRoutesCount == 1) {
      buffer.writeln(
        '  - NOTA: OSRM devolvió 1 única ruta física nativa. '
        'Si requirió desvío público, fue generado y validado contra el registro vial.',
      );
    }

    for (int i = 0; i < validatedRoutes.length; i++) {
      final r = validatedRoutes[i];
      buffer.writeln(
        '  - [Ruta $i] "${r.routeName}" (${r.summary}) | ${r.totalDistanceKm.toStringAsFixed(2)} km | '
        '${r.estimatedDuration.inMinutes} min | Pública=${r.isPubliclyPassable} | '
        'Estado=${r.validation.status} | Avisos=${r.validation.warnings.length}',
      );
      if (r.validation.warnings.isNotEmpty) {
        for (final w in r.validation.warnings) {
          buffer.writeln('      ! Aviso vial: $w');
        }
      }
    }

    if (finalResultPresented != null) {
      buffer.writeln(
        '  - Resultado final mostrado al usuario: $finalResultPresented',
      );
    }

    debugPrint(buffer.toString());
  }
}
