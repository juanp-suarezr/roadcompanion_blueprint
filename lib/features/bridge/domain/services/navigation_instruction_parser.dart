import '../../../../domain/entities/maneuver_type.dart';
import '../entities/bridge_instruction_status.dart';
import '../entities/bridge_navigation_instruction.dart';
import '../entities/bridge_source_type.dart';

/// Analizador sintáctico independiente y determinista para instrucciones
/// de navegación provenientes de fuentes externas en ESTELA Bridge.
///
/// Transforma textos no estructurados (por ejemplo títulos y cuerpos de
/// notificaciones interceptadas) en modelos inmutables [BridgeNavigationInstruction].
///
/// NOTA DE INGENIERÍA Y ADVERTENCIA DE VIABILIDAD:
/// Este parser implementa patrones sintácticos de referencia iniciales.
/// No debe asumirse que representa con exactitud la totalidad de cadenas
/// emitidas por distintas versiones de Google Maps y Waze hasta recopilar
/// y auditar volcados de telemetría auténticos en el Samsung Galaxy A35.
class NavigationInstructionParser {
  const NavigationInstructionParser();

  // Expresiones regulares para extracción de métricas de distancia.
  static final RegExp _kmRegex = RegExp(
    r'(?:en\s+)?(\d+(?:[.,]\d+)?)\s*(?:km|kil[oó]metros?)\b',
    caseSensitive: false,
  );

  static final RegExp _meterRegex = RegExp(
    r'(?:en\s+)?(\d+)\s*(?:m|metros?)\b',
    caseSensitive: false,
  );

  static final RegExp _feetRegex = RegExp(
    r'(?:en\s+)?(\d+)\s*(?:ft|pies?)\b',
    caseSensitive: false,
  );

  static final RegExp _milesRegex = RegExp(
    r'(?:en\s+)?(\d+(?:[.,]\d+)?)\s*(?:mi|millas?)\b',
    caseSensitive: false,
  );

  // Expresión para detectar número de salida en rotondas (1 a 8).
  static final RegExp _roundaboutExitRegex = RegExp(
    r'(?:toma|take)?\s*(?:la)?\s*([1-8])(?:[ªaºo°]|\.ª|\.º|st|nd|rd|th)?\s*salida|\bsalida\s*([1-8])|\b([1-8])(?:st|nd|rd|th)\s*exit',
    caseSensitive: false,
  );

  // Expresión para extracción heurística de calle o vía de destino.
  static final RegExp _streetConnectorRegex = RegExp(
    r'(?:hacia|en|por|onto|towards?|on)\s+([A-Za-z0-9áéíóúÁÉÍÓÚñÑ#°.\-\s]{3,40})',
    caseSensitive: false,
  );

  /// Procesa los textos disponibles de una notificación o mensaje externo
  /// y construye una [BridgeNavigationInstruction] rigurosamente clasificada.
  BridgeNavigationInstruction parse({
    String? rawTitle,
    String? rawText,
    String? rawSubText,
    required BridgeSourceType source,
    DateTime? receivedAt,
  }) {
    final effectiveReceivedAt = receivedAt ?? DateTime.now();

    final title = (rawTitle ?? '').trim();
    final body = (rawText ?? '').trim();
    final sub = (rawSubText ?? '').trim();

    final combinedText = [
      title,
      body,
      sub,
    ].where((part) => part.isNotEmpty).join(' — ');

    if (combinedText.isEmpty) {
      return BridgeNavigationInstruction(
        source: source,
        maneuverType: ManeuverType.unknown,
        rawText: '',
        rawTitle: rawTitle,
        receivedAt: effectiveReceivedAt,
        status: BridgeInstructionStatus.unrecognized,
      );
    }

    // 1. Extraer distancia si está presente en cualquiera de los fragmentos.
    final distanceResult = _extractDistance(title, body, sub);

    // 2. Extraer maniobra y salida de rotonda.
    final (maneuverType, exitNumber) = _detectManeuver(combinedText);

    // 3. Extraer calle destino si la hay.
    final street = _extractStreet(title, body);

    // 4. Determinar estado de validez de forma determinista y segura.
    final status = _determineStatus(
      combinedText: combinedText,
      maneuverType: maneuverType,
      hasDistance: distanceResult != null,
    );

    return BridgeNavigationInstruction(
      source: source,
      maneuverType: maneuverType,
      distanceMeters: distanceResult?.meters,
      rawDistanceText: distanceResult?.rawText,
      rawText: combinedText,
      rawTitle: title.isNotEmpty ? title : null,
      destinationStreet: street,
      roundaboutExit: exitNumber,
      receivedAt: effectiveReceivedAt,
      status: status,
    );
  }

  /// Extrae la distancia en metros a partir de patrones estándar en español e inglés.
  /// No infiere ni inventa distancias si no existe concordancia explícita.
  _DistanceResult? _extractDistance(String title, String body, String sub) {
    // Buscar prioritariamente en el título o cuerpo donde suele venir la maniobra inmediata.
    final candidateTexts = [title, body, sub].where((t) => t.isNotEmpty);

    for (final text in candidateTexts) {
      // Kilómetros (ej. "1,2 km", "1.2 km", "en 500 km")
      final kmMatch = _kmRegex.firstMatch(text);
      if (kmMatch != null) {
        final rawNum = kmMatch.group(1)!.replaceAll(',', '.');
        final value = double.tryParse(rawNum);
        if (value != null && value >= 0 && value.isFinite) {
          return _DistanceResult(
            meters: (value * 1000).round(),
            rawText: kmMatch.group(0)!.trim(),
          );
        }
      }

      // Metros (ej. "400 m", "50 metros", "en 100 m")
      final meterMatch = _meterRegex.firstMatch(text);
      if (meterMatch != null) {
        final value = int.tryParse(meterMatch.group(1)!);
        if (value != null && value >= 0) {
          return _DistanceResult(
            meters: value,
            rawText: meterMatch.group(0)!.trim(),
          );
        }
      }

      // Millas (ej. "1.5 mi")
      final milesMatch = _milesRegex.firstMatch(text);
      if (milesMatch != null) {
        final rawNum = milesMatch.group(1)!.replaceAll(',', '.');
        final value = double.tryParse(rawNum);
        if (value != null && value >= 0 && value.isFinite) {
          return _DistanceResult(
            meters: (value * 1609.34).round(),
            rawText: milesMatch.group(0)!.trim(),
          );
        }
      }

      // Pies (ej. "500 ft", "1000 pies")
      final feetMatch = _feetRegex.firstMatch(text);
      if (feetMatch != null) {
        final value = int.tryParse(feetMatch.group(1)!);
        if (value != null && value >= 0) {
          return _DistanceResult(
            meters: (value * 0.3048).round(),
            rawText: feetMatch.group(0)!.trim(),
          );
        }
      }
    }

    return null;
  }

  /// Identifica la maniobra y posibles atributos secundarios (número de salida en rotonda).
  (ManeuverType, int?) _detectManeuver(String text) {
    final lower = text.toLowerCase();

    // Textos informativos de estado o ruido que no deben ser interpretados como giros:
    if (_isNonManeuverStatus(lower)) {
      return (ManeuverType.unknown, null);
    }

    // 1. Llegada / Destino
    if (lower.contains('has llegado') ||
        lower.contains('llegarás a tu destino') ||
        lower.contains('llegaras a tu destino') ||
        lower.contains('destino alcanzado') ||
        lower.contains('you have arrived') ||
        lower.contains('arrived at destination') ||
        lower.contains('destino a la')) {
      return (ManeuverType.arrive, null);
    }

    // 2. Retorno / Cambio de sentido
    if (lower.contains('cambio de sentido') ||
        lower.contains('vuelta en u') ||
        lower.contains('retorno') ||
        lower.contains('u-turn') ||
        lower.contains('uturn') ||
        lower.contains('make a u-turn')) {
      return (ManeuverType.uTurn, null);
    }

    // 3. Rotonda / Glorieta
    if (lower.contains('rotonda') ||
        lower.contains('glorieta') ||
        lower.contains('roundabout') ||
        lower.contains('rotary')) {
      final exitMatch = _roundaboutExitRegex.firstMatch(text);
      int? exitNumber;
      if (exitMatch != null) {
        final captured =
            exitMatch.group(1) ?? exitMatch.group(2) ?? exitMatch.group(3);
        if (captured != null) {
          exitNumber = int.tryParse(captured);
        }
      }
      return (ManeuverType.roundabout, exitNumber);
    }

    // 4. Giros a la izquierda (con discriminación de ángulo)
    if (lower.contains('pronunciado a la izquierda') ||
        lower.contains('cerrado a la izquierda') ||
        lower.contains('brusco a la izquierda') ||
        lower.contains('sharp left')) {
      return (ManeuverType.sharpLeft, null);
    }

    if (lower.contains('suave a la izquierda') ||
        lower.contains('leve a la izquierda') ||
        lower.contains('mantente a la izquierda') ||
        lower.contains('manten a la izquierda') ||
        lower.contains('slight left') ||
        lower.contains('keep left') ||
        lower.contains('bifurcacion a la izquierda') ||
        lower.contains('bifurcación a la izquierda')) {
      return (ManeuverType.slightLeft, null);
    }

    if (lower.contains('a la izquierda') ||
        lower.contains('hacia la izquierda') ||
        lower.contains('turn left')) {
      return (ManeuverType.left, null);
    }

    // 5. Giros a la derecha (con discriminación de ángulo)
    if (lower.contains('pronunciado a la derecha') ||
        lower.contains('cerrado a la derecha') ||
        lower.contains('brusco a la derecha') ||
        lower.contains('sharp right')) {
      return (ManeuverType.sharpRight, null);
    }

    if (lower.contains('suave a la derecha') ||
        lower.contains('leve a la derecha') ||
        lower.contains('mantente a la derecha') ||
        lower.contains('manten a la derecha') ||
        lower.contains('slight right') ||
        lower.contains('keep right') ||
        lower.contains('bifurcacion a la derecha') ||
        lower.contains('bifurcación a la derecha')) {
      return (ManeuverType.slightRight, null);
    }

    if (lower.contains('a la derecha') ||
        lower.contains('hacia la derecha') ||
        lower.contains('turn right')) {
      return (ManeuverType.right, null);
    }

    // 6. Continuar recto / seguir
    if (lower.contains('continúa recto') ||
        lower.contains('continua recto') ||
        lower.contains('sigue recto') ||
        lower.contains('continúa por') ||
        lower.contains('continua por') ||
        lower.contains('sigue por') ||
        lower.contains('head straight') ||
        lower.contains('continue on') ||
        lower.contains('straight ahead')) {
      return (ManeuverType.straight, null);
    }

    // 7. Salida / Partida inicial
    if (lower.contains('dirígete hacia') ||
        lower.contains('dirigete hacia') ||
        lower.contains('inicia el viaje') ||
        lower.contains('head north') ||
        lower.contains('head south') ||
        lower.contains('head east') ||
        lower.contains('head west')) {
      return (ManeuverType.depart, null);
    }

    // No se reconoció maniobra explícita.
    // REGLA CRÍTICA: Bajo ningún concepto asignar straight por defecto.
    return (ManeuverType.unknown, null);
  }

  /// Determina el estado de validez de la instrucción.
  BridgeInstructionStatus _determineStatus({
    required String combinedText,
    required ManeuverType maneuverType,
    required bool hasDistance,
  }) {
    if (maneuverType != ManeuverType.unknown) {
      return BridgeInstructionStatus.recognized;
    }

    // Si no hay maniobra pero hay distancia confirmada, es una indicación parcial/incompleta.
    if (hasDistance) {
      return BridgeInstructionStatus.incomplete;
    }

    return BridgeInstructionStatus.unrecognized;
  }

  /// Filtra textos habituales en notificaciones de mapas que NO son maniobras.
  bool _isNonManeuverStatus(String lower) {
    return lower.contains('buscando gps') ||
        lower.contains('buscando señal') ||
        lower.contains('buscando senal') ||
        lower.contains('calculando ruta') ||
        lower.contains('recalculando') ||
        lower.contains('ruta más rápida') ||
        lower.contains('ruta mas rapida') ||
        lower.contains('tráfico denso') ||
        lower.contains('trafico denso') ||
        lower.contains('precaución') ||
        lower.contains('precaucion') ||
        lower.contains('radar fijo') ||
        lower.contains('radar móvil') ||
        lower.contains('bienvenido a waze') ||
        lower.contains('sesión iniciada') ||
        lower.contains('sesion iniciada');
  }

  /// Extracción heurística del nombre de la vía de destino.
  String? _extractStreet(String title, String body) {
    // Comprobar en el cuerpo y en el título
    for (final text in [body, title]) {
      final matches = _streetConnectorRegex.allMatches(text);
      for (final match in matches) {
        final candidate = match.group(1)!.trim();
        // Si el fragmento comienza con distancia (ej. "400 m hacia Carrera 7")
        if (_meterRegex.hasMatch(candidate) || _kmRegex.hasMatch(candidate)) {
          final innerMatches = _streetConnectorRegex.allMatches(candidate);
          for (final inner in innerMatches) {
            final innerStreet = inner.group(1)!.trim();
            if (!_meterRegex.hasMatch(innerStreet) &&
                !_kmRegex.hasMatch(innerStreet)) {
              return innerStreet.replaceAll(RegExp(r'[,.\-]+$'), '').trim();
            }
          }
          continue;
        }
        return candidate.replaceAll(RegExp(r'[,.\-]+$'), '').trim();
      }
    }
    return null;
  }
}

class _DistanceResult {
  final int meters;
  final String rawText;

  const _DistanceResult({required this.meters, required this.rawText});
}
