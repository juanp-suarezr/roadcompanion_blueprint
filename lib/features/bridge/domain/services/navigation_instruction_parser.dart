import '../../../../domain/entities/maneuver_type.dart';
import '../entities/bridge_instruction_status.dart';
import '../entities/bridge_navigation_instruction.dart';
import '../entities/bridge_source_type.dart';

/// Analizador sintáctico independiente y determinista para instrucciones
/// de navegación provenientes de fuentes externas en ESTELA Bridge.
///
/// Transforma textos no estructurados (por ejemplo títulos, cuerpos y RemoteViews de
/// notificaciones interceptadas) en modelos inmutables [BridgeNavigationInstruction].
class NavigationInstructionParser {
  const NavigationInstructionParser();

  // Expresiones regulares para extracción de métricas de distancia.
  static final RegExp _kmRegex = RegExp(
    r'(?:en\s+)?(\d+(?:[.,]\d+)?)\s*(?:km|kil[oó]metros?)\b',
    caseSensitive: false,
  );

  static final RegExp _meterRegex = RegExp(
    r'(?:en\s+)?(\d+)\s*(?:m|mts?|metros?)\b',
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
    r'(?:toma|tome|take)?\s*(?:la)?\s*([1-8])(?:[ªaºo°]|ra|da|ta|va|\.ª|\.º|st|nd|rd|th)?\s*salida|\bsalida\s*([1-8])|\b([1-8])(?:st|nd|rd|th)\s*exit',
    caseSensitive: false,
  );

  // Expresión para extracción heurística de calle o vía de destino (incluyendo nomenclatura vial de Colombia).
  static final RegExp _streetConnectorRegex = RegExp(
    r'(?:hacia|en|por|onto|towards?|on)\s+([A-Za-z0-9áéíóúÁÉÍÓÚñÑ#°ªº/.\-\s]{3,45})',
    caseSensitive: false,
  );

  static const Set<String> _irrelevantRemoteLabels = {
    'waze',
    'google maps',
    'maps',
    'cerrar',
    'salir',
    'detener',
    'cancelar',
    'apagar',
    'silenciar',
    'stop',
    'exit',
    'dismiss',
    'close',
    'mute',
  };

  /// Procesa los textos disponibles de una notificación o mensaje externo
  /// y construye una [BridgeNavigationInstruction] rigurosamente clasificada.
  BridgeNavigationInstruction parse({
    String? rawTitle,
    String? rawText,
    String? rawSubText,
    required BridgeSourceType source,
    DateTime? receivedAt,
    List<String> availableExtras = const [],
    List<String> remoteViewsTexts = const [],
    String? notificationKey,
    String? notificationCategory,
  }) {
    final effectiveReceivedAt = receivedAt ?? DateTime.now();

    var title = (rawTitle ?? '').trim();
    var body = (rawText ?? '').trim();
    final sub = (rawSubText ?? '').trim();

    // Si los campos estándar vienen vacíos o solo contienen el nombre de la app,
    // aprovechar los fragmentos útiles extraídos de RemoteViews.
    final usefulRemoteTexts = remoteViewsTexts
        .map((t) => t.trim())
        .where(
          (t) =>
              t.isNotEmpty &&
              !_irrelevantRemoteLabels.contains(t.toLowerCase()),
        )
        .toList(growable: false);

    if (usefulRemoteTexts.isNotEmpty) {
      if (title.isEmpty ||
          _irrelevantRemoteLabels.contains(title.toLowerCase())) {
        title = usefulRemoteTexts.first;
      }
      if (body.isEmpty || _isAppRunningOnlyBanner(body.toLowerCase())) {
        body = usefulRemoteTexts.length > 1
            ? usefulRemoteTexts.sublist(1).join(' — ')
            : (title != usefulRemoteTexts.first ? usefulRemoteTexts.first : '');
      }
    }

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
        isEmptyNotification: true,
        notificationKey: notificationKey,
        notificationCategory: notificationCategory,
        discardReason:
            'Notificación recibida sin texto extraíble (notification_text_empty)',
        availableExtras: availableExtras,
        remoteViewsTexts: remoteViewsTexts,
      );
    }

    final lowerCombined = combinedText.toLowerCase();

    // 0. Detectar si es únicamente una notificación persistente de "aplicación en ejecución"
    // (ej. "Waze — En ejecución. Toca para abrir." / "Waze — Running. Tap to open.") y NO una instrucción de giro.
    if (_isAppRunningOnlyBanner(lowerCombined)) {
      return BridgeNavigationInstruction(
        source: source,
        maneuverType: ManeuverType.unknown,
        rawText: combinedText,
        rawTitle: title.isNotEmpty ? title : null,
        receivedAt: effectiveReceivedAt,
        status: BridgeInstructionStatus.unrecognized,
        isAppRunningNotification: true,
        isEmptyNotification: false,
        notificationKey: notificationKey,
        notificationCategory: notificationCategory,
        discardReason:
            'Notificación de aplicación activa en segundo plano (sin maniobra de ruta)',
        availableExtras: availableExtras,
        remoteViewsTexts: remoteViewsTexts,
      );
    }

    // 1. Extraer distancia únicamente en título, cuerpo, subText o RemoteViews.
    final distanceResult = _extractDistance(
      title,
      body,
      sub,
      usefulRemoteTexts,
    );

    // 2. Extraer maniobra giro a giro real y salida de rotonda (evaluando título/cuerpo antes que avisos secundarios).
    final primaryText = [
      title,
      body,
      ...usefulRemoteTexts,
    ].where((p) => p.isNotEmpty).join(' — ');
    final (maneuverType, exitNumber) = _detectManeuver(
      primaryText.isNotEmpty ? primaryText : combinedText,
    );

    // 3. Clasificar explícitamente si es orientación cardinal ("Head north"), inicio ("Starting navigation"),
    // recálculo ("Rerouting") o aviso de tráfico sin maniobra giro a giro válida.
    final nonManeuverReason = maneuverType == ManeuverType.unknown
        ? _classifyNonManeuverReason(lowerCombined)
        : null;

    // 4. Extraer calle destino únicamente cuando exista una maniobra real.
    final street =
        (maneuverType == ManeuverType.unknown ||
            _isNonManeuverStatus(lowerCombined))
        ? null
        : _extractStreet(title, body, usefulRemoteTexts);

    // Si la maniobra es llegada a destino y no incluye cifra explícita en metros, usar 0 m.
    final effectiveDistanceMeters = nonManeuverReason != null
        ? null
        : (distanceResult?.meters ??
              (maneuverType == ManeuverType.arrive ? 0 : null));

    // 5. Determinar estado de validez de forma determinista y segura.
    final status = nonManeuverReason != null
        ? BridgeInstructionStatus.unrecognized
        : _determineStatus(
            combinedText: combinedText,
            maneuverType: maneuverType,
            hasDistance: effectiveDistanceMeters != null,
          );

    final String? discardReason =
        nonManeuverReason ??
        switch (status) {
          BridgeInstructionStatus.recognized =>
            effectiveDistanceMeters == null
                ? 'Maniobra reconocida (${maneuverType.name}) pero sin distancia numérica'
                : null,
          BridgeInstructionStatus.incomplete =>
            'Notificación de navegación parcial (distancia sin verbo de giro reconocible)',
          BridgeInstructionStatus.unrecognized =>
            'Notificación sin maniobra ni distancia vial reconocible',
          BridgeInstructionStatus.stale => 'Instrucción obsoleta o cancelada',
        };

    return BridgeNavigationInstruction(
      source: source,
      maneuverType: maneuverType,
      distanceMeters: effectiveDistanceMeters,
      rawDistanceText: effectiveDistanceMeters != null
          ? distanceResult?.rawText
          : null,
      rawText: combinedText,
      rawTitle: title.isNotEmpty ? title : null,
      destinationStreet: street,
      roundaboutExit: exitNumber,
      receivedAt: effectiveReceivedAt,
      status: status,
      isAppRunningNotification: false,
      isEmptyNotification: false,
      notificationKey: notificationKey,
      notificationCategory: notificationCategory,
      discardReason: discardReason,
      availableExtras: availableExtras,
      remoteViewsTexts: remoteViewsTexts,
    );
  }

  /// Perfil de parseo específico para notificaciones de Waze (`com.waze`).
  BridgeNavigationInstruction parseWaze({
    String? rawTitle,
    String? rawText,
    String? rawSubText,
    DateTime? receivedAt,
    List<String> availableExtras = const [],
    List<String> remoteViewsTexts = const [],
    String? notificationKey,
    String? notificationCategory,
  }) {
    return parse(
      rawTitle: rawTitle,
      rawText: rawText,
      rawSubText: rawSubText,
      source: BridgeSourceType.waze,
      receivedAt: receivedAt,
      availableExtras: availableExtras,
      remoteViewsTexts: remoteViewsTexts,
      notificationKey: notificationKey,
      notificationCategory: notificationCategory,
    );
  }

  /// Perfil de parseo específico para notificaciones de Google Maps (`com.google.android.apps.maps`).
  BridgeNavigationInstruction parseGoogleMaps({
    String? rawTitle,
    String? rawText,
    String? rawSubText,
    DateTime? receivedAt,
    List<String> availableExtras = const [],
    List<String> remoteViewsTexts = const [],
    String? notificationKey,
    String? notificationCategory,
  }) {
    return parse(
      rawTitle: rawTitle,
      rawText: rawText,
      rawSubText: rawSubText,
      source: BridgeSourceType.googleMaps,
      receivedAt: receivedAt,
      availableExtras: availableExtras,
      remoteViewsTexts: remoteViewsTexts,
      notificationKey: notificationKey,
      notificationCategory: notificationCategory,
    );
  }

  /// Extrae la distancia en metros a partir de patrones estándar en español e inglés.
  /// No infiere ni inventa distancias si no existe concordancia explícita.
  _DistanceResult? _extractDistance(
    String title,
    String body,
    String sub, [
    List<String> remoteTexts = const [],
  ]) {
    // Buscar prioritariamente en el título o cuerpo donde suele venir la maniobra inmediata.
    final candidateTexts = [
      title,
      body,
      ...remoteTexts,
      sub,
    ].where((t) => t.isNotEmpty);

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

      // Metros (ej. "400 m", "50 metros", "en 100 m", "300 mts")
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
        lower.contains('ha llegado') ||
        lower.contains('llegaste') ||
        lower.contains('llegó a') ||
        lower.contains('llego a') ||
        lower.contains('llegarás a tu destino') ||
        lower.contains('llegaras a tu destino') ||
        lower.contains('llegará a su destino') ||
        lower.contains('llegara a su destino') ||
        lower.contains('destino alcanzado') ||
        lower.contains('you have arrived') ||
        lower.contains('arrived at destination') ||
        lower.contains('destino a la')) {
      return (ManeuverType.arrive, null);
    }

    // 2. Retorno / Cambio de sentido
    if (lower.contains('cambio de sentido') ||
        lower.contains('vuelta en u') ||
        lower.contains('giro en u') ||
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
      } else {
        exitNumber = _extractWordRoundaboutExit(lower);
      }
      return (ManeuverType.roundabout, exitNumber);
    }

    // 4. Giros a la izquierda (con discriminación de ángulo y vocabulario Waze/Colombia)
    if (lower.contains('pronunciado a la izquierda') ||
        lower.contains('cerrado a la izquierda') ||
        lower.contains('brusco a la izquierda') ||
        lower.contains('fuerte a la izquierda') ||
        lower.contains('sharp left')) {
      return (ManeuverType.sharpLeft, null);
    }

    if (lower.contains('suave a la izquierda') ||
        lower.contains('leve a la izquierda') ||
        lower.contains('levemente a la izquierda') ||
        lower.contains('ligeramente a la izquierda') ||
        lower.contains('mantente a la izquierda') ||
        lower.contains('manten a la izquierda') ||
        lower.contains('manténgase a la izquierda') ||
        lower.contains('mantengase a la izquierda') ||
        lower.contains('mantente a la izq') ||
        lower.contains('usa el carril izquierdo') ||
        lower.contains('use el carril izquierdo') ||
        lower.contains('sal a la izquierda') ||
        lower.contains('sal por la izquierda') ||
        lower.contains('salga a la izquierda') ||
        lower.contains('salida a la izquierda') ||
        lower.contains('toma la salida a la izquierda') ||
        lower.contains('tome la salida a la izquierda') ||
        lower.contains('slight left') ||
        lower.contains('keep left') ||
        lower.contains('exit left') ||
        lower.contains('bifurcacion a la izquierda') ||
        lower.contains('bifurcación a la izquierda')) {
      return (ManeuverType.slightLeft, null);
    }

    if (lower.contains('a la izquierda') ||
        lower.contains('hacia la izquierda') ||
        lower.contains('dobla a la izquierda') ||
        lower.contains('doble a la izquierda') ||
        lower.contains('voltea a la izquierda') ||
        lower.contains('voltee a la izquierda') ||
        lower.contains('vira a la izquierda') ||
        lower.contains('vire a la izquierda') ||
        lower.contains('toma a la izquierda') ||
        lower.contains('tome a la izquierda') ||
        lower.contains('gira a la izq') ||
        lower.contains('gire a la izq') ||
        lower.contains('izquierda en ') ||
        lower.contains('izquierda hacia ') ||
        lower.contains('izquierda por ') ||
        lower.contains('turn left')) {
      return (ManeuverType.left, null);
    }

    // 5. Giros a la derecha (con discriminación de ángulo y vocabulario Waze/Colombia)
    if (lower.contains('pronunciado a la derecha') ||
        lower.contains('cerrado a la derecha') ||
        lower.contains('brusco a la derecha') ||
        lower.contains('fuerte a la derecha') ||
        lower.contains('sharp right')) {
      return (ManeuverType.sharpRight, null);
    }

    if (lower.contains('suave a la derecha') ||
        lower.contains('leve a la derecha') ||
        lower.contains('levemente a la derecha') ||
        lower.contains('ligeramente a la derecha') ||
        lower.contains('mantente a la derecha') ||
        lower.contains('manten a la derecha') ||
        lower.contains('manténgase a la derecha') ||
        lower.contains('mantengase a la derecha') ||
        lower.contains('mantente a la der') ||
        lower.contains('usa el carril derecho') ||
        lower.contains('use el carril derecho') ||
        lower.contains('sal a la derecha') ||
        lower.contains('sal por la derecha') ||
        lower.contains('salga a la derecha') ||
        lower.contains('salida a la derecha') ||
        lower.contains('toma la salida a la derecha') ||
        lower.contains('tome la salida a la derecha') ||
        lower.contains('slight right') ||
        lower.contains('keep right') ||
        lower.contains('exit right') ||
        lower.contains('bifurcacion a la derecha') ||
        lower.contains('bifurcación a la derecha')) {
      return (ManeuverType.slightRight, null);
    }

    if (lower.contains('a la derecha') ||
        lower.contains('hacia la derecha') ||
        lower.contains('dobla a la derecha') ||
        lower.contains('doble a la derecha') ||
        lower.contains('voltea a la derecha') ||
        lower.contains('voltee a la derecha') ||
        lower.contains('vira a la derecha') ||
        lower.contains('vire a la derecha') ||
        lower.contains('toma a la derecha') ||
        lower.contains('tome a la derecha') ||
        lower.contains('gira a la der') ||
        lower.contains('gire a la der') ||
        lower.contains('derecha en ') ||
        lower.contains('derecha hacia ') ||
        lower.contains('derecha por ') ||
        lower.contains('turn right')) {
      return (ManeuverType.right, null);
    }

    // 6. Continuar recto / seguir derecho
    if (lower.contains('continúa recto') ||
        lower.contains('continua recto') ||
        lower.contains('continúe recto') ||
        lower.contains('continue recto') ||
        lower.contains('sigue recto') ||
        lower.contains('siga recto') ||
        lower.contains('sigue derecho') ||
        lower.contains('siga derecho') ||
        lower.contains('sigue directo') ||
        lower.contains('continúa derecho') ||
        lower.contains('continua derecho') ||
        lower.contains('continúe derecho') ||
        lower.contains('continúa por') ||
        lower.contains('continua por') ||
        lower.contains('continúe por') ||
        lower.contains('sigue por') ||
        lower.contains('siga por') ||
        lower.contains('head straight') ||
        lower.contains('continue on') ||
        lower.contains('straight ahead')) {
      return (ManeuverType.straight, null);
    }

    // NOTA DE SEGURIDAD FÍSICA:
    // Las orientaciones cardinales ("Head north", "Head south", "Dirígete al norte")
    // emitidas al iniciar ruta con la moto estacionada NO son maniobras giro a giro
    // y NUNCA deben convertirse en seguir recto ni generar paquetes BLE.
    // REGLA CRÍTICA: Bajo ningún concepto asignar straight o depart por defecto.
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

  int? _extractWordRoundaboutExit(String lower) {
    if (lower.contains('primera salida')) return 1;
    if (lower.contains('segunda salida')) return 2;
    if (lower.contains('tercera salida')) return 3;
    if (lower.contains('cuarta salida')) return 4;
    if (lower.contains('quinta salida')) return 5;
    if (lower.contains('sexta salida')) return 6;
    return null;
  }

  /// Identifica notificaciones persistentes de aplicación activa en segundo plano
  /// (ej. "Waze — En ejecución. Toca para abrir." / "Waze — Running. Tap to open.")
  /// que no contienen instrucciones de ruta.
  bool _isAppRunningOnlyBanner(String lower) {
    if (lower.contains('en ejecución') ||
        lower.contains('en ejecucion') ||
        lower.contains('toca para abrir') ||
        lower.contains('toque para abrir') ||
        lower.contains('tap to open') ||
        lower.contains('touch to open') ||
        lower.contains('running.') ||
        lower.contains('running in background') ||
        lower.contains('return to waze') ||
        lower.contains('volver a waze') ||
        lower.contains('en segundo plano')) {
      return true;
    }
    if (RegExp(r'\bwaze\s*[—\-:]\s*running\b').hasMatch(lower) ||
        lower.trim() == 'running') {
      return true;
    }
    return false;
  }

  bool _isCardinalHeadingPrompt(String lower) {
    return RegExp(
          r'\bhead\s+(?:north|south|east|west|northeast|northwest|southeast|southwest)\b',
        ).hasMatch(lower) ||
        lower.contains('dirígete al ') ||
        lower.contains('dirigete al ') ||
        lower.contains('diríjase al ') ||
        lower.contains('dirijase al ') ||
        lower.contains('dirígete hacia') ||
        lower.contains('dirigete hacia') ||
        lower.contains('diríjase hacia') ||
        lower.contains('dirijase hacia');
  }

  String? _classifyNonManeuverReason(String lower) {
    if (_isCardinalHeadingPrompt(lower)) {
      return 'Orientación cardinal inicial (ej. "Head north" / brújula): descartada para no inventar flecha recta en el Tripper';
    }
    if (lower.contains('starting navigation') ||
        lower.contains('iniciando navegación') ||
        lower.contains('iniciando navegacion') ||
        lower.contains('inicia el viaje')) {
      return 'Evento de inicio de navegación ("Starting navigation"): esperando primera maniobra giro a giro';
    }
    if (lower.contains('rerouting') ||
        lower.contains('recalculating') ||
        lower.contains('recalculando') ||
        lower.contains('calculando ruta')) {
      return 'Evento de recálculo de ruta ("Rerouting"): descartado para no enviar maniobra ficticia';
    }
    if (lower.contains('buscando gps') ||
        lower.contains('buscando señal') ||
        lower.contains('buscando senal') ||
        lower.contains('searching for gps') ||
        lower.contains('waiting for location')) {
      return 'Estado de búsqueda de señal GPS (sin maniobra)';
    }
    if (lower.contains('tráfico') ||
        lower.contains('trafico') ||
        lower.contains('traffic') ||
        lower.contains('faster route') ||
        lower.contains('ruta más rápida') ||
        lower.contains('ruta mas rapida') ||
        lower.contains('precaución') ||
        lower.contains('precaucion') ||
        lower.contains('radar fijo') ||
        lower.contains('radar móvil') ||
        lower.contains('accidente') ||
        lower.contains('crash') ||
        lower.contains('delay') ||
        lower.contains('demora')) {
      return 'Aviso informativo de tráfico o estado vial (no es maniobra giro a giro)';
    }
    return null;
  }

  /// Filtra textos habituales en notificaciones de mapas que NO son maniobras.
  bool _isNonManeuverStatus(String lower) {
    return _isAppRunningOnlyBanner(lower) ||
        _classifyNonManeuverReason(lower) != null ||
        lower.contains('bienvenido a waze') ||
        lower.contains('sesión iniciada') ||
        lower.contains('sesion iniciada');
  }

  static const List<String> _nonStreetTokens = [
    'ejecución',
    'ejecucion',
    'toca para abrir',
    'toque para abrir',
    'segundo plano',
    'la izquierda',
    'la derecha',
    'la rotonda',
    'la glorieta',
    'tu destino',
    'su destino',
  ];

  /// Extracción heurística del nombre de la vía de destino.
  String? _extractStreet(
    String title,
    String body, [
    List<String> remoteTexts = const [],
  ]) {
    // Comprobar en el cuerpo, en el título y en los fragmentos de RemoteViews
    for (final text in [body, title, ...remoteTexts]) {
      if (_isNonManeuverStatus(text.toLowerCase())) continue;
      final matches = _streetConnectorRegex.allMatches(text);
      for (final match in matches) {
        final candidate = match.group(1)!.trim();
        final lowerCandidate = candidate.toLowerCase();
        if (_nonStreetTokens.any((tok) => lowerCandidate.contains(tok))) {
          continue;
        }
        // Si el fragmento comienza con distancia (ej. "400 m hacia Carrera 7")
        if (_meterRegex.hasMatch(candidate) || _kmRegex.hasMatch(candidate)) {
          final innerMatches = _streetConnectorRegex.allMatches(candidate);
          for (final inner in innerMatches) {
            final innerStreet = inner.group(1)!.trim();
            final lowerInner = innerStreet.toLowerCase();
            if (!_meterRegex.hasMatch(innerStreet) &&
                !_kmRegex.hasMatch(innerStreet) &&
                !_nonStreetTokens.any((tok) => lowerInner.contains(tok))) {
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
