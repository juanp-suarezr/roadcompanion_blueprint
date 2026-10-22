/// Dispositivo Bluetooth detectado durante el escaneo y su grado de compatibilidad
/// técnica con el Royal Enfield Tripper Pod (Meteor 350).
class TripperDevice {
  /// Identificador único del dispositivo (MAC en Android o UUID en iOS).
  final String id;

  /// Nombre anunciado públicamente en el paquete publicitario BLE.
  final String name;

  /// Intensidad de la señal de radio en dBm (RSSI).
  final int rssi;

  /// Lista de UUIDs de servicios anunciados en el paquete publicitario.
  final List<String> serviceUuids;

  /// Datos técnicos del fabricante (Manufacturer Data).
  final Map<int, List<int>> manufacturerData;

  /// Indica si existen evidencias técnicas de que se trata de un Tripper Pod.
  final bool isTripperCandidate;

  /// Nivel de confianza ('Alta', 'Media', 'Baja') basado en evidencias.
  final String confidenceLevel;

  /// Explicación técnica de la evaluación.
  final String technicalEvidence;

  const TripperDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    this.manufacturerData = const {},
    required this.isTripperCandidate,
    required this.confidenceLevel,
    required this.technicalEvidence,
  });

  /// Evalúa un dispositivo descubierto para determinar si es un candidato a Tripper Pod.
  factory TripperDevice.evaluate({
    required String id,
    required String name,
    required int rssi,
    List<String> serviceUuids = const [],
    Map<int, List<int>> manufacturerData = const {},
  }) {
    final trimmedName = name.trim();
    final cleanName = trimmedName.toUpperCase();
    final bool isExactReDisp = cleanName == 'RE_DISP' || cleanName.startsWith('RE_DISP');
    final bool hasNameMatch =
        isExactReDisp ||
        cleanName.contains('ROYAL') ||
        cleanName.contains('ENFIELD') ||
        cleanName.contains('TRIPPER') ||
        cleanName.contains('RE_') ||
        cleanName.contains('METEOR');

    // UUID específico del Tripper Pod (NXP Wireless UART: 01FF0100-BA5E-F4EE-5CA1-EB1E5E4B1CE0)
    final bool hasNxpTripperUuid = serviceUuids.any((u) {
      final norm = u.toLowerCase();
      return norm.contains('01ff0100') || norm.contains('01ff0101');
    });

    // Prefijo MAC registrado de NXP Semiconductor (00:60:37)
    final bool hasNxpMac = id.trim().toUpperCase().startsWith('00:60:37');

    // UUIDs comunes en módulos UART/Serie o referencias de la industria
    final bool hasKnownSerialUuid = hasNxpTripperUuid ||
        serviceUuids.any((u) {
          final norm = u.toLowerCase();
          return norm.contains('ffe0') ||
              norm.contains('fff0') ||
              norm.contains('fe95') ||
              norm.contains('1800') ||
              norm.contains('180a');
        });

    bool isCandidate = false;
    String confidence = 'Baja';
    String evidence;

    if (isExactReDisp && (hasNxpTripperUuid || hasNxpMac)) {
      isCandidate = true;
      confidence = 'Alta';
      evidence =
          'Coincidencia exacta con Tripper Pod (Nombre "RE_DISP" y prefijo MAC NXP / UUID NXP Wireless UART confirmado).';
    } else if (isExactReDisp) {
      isCandidate = true;
      confidence = 'Alta';
      evidence =
          'Nombre anunciado idéntico al Tripper Pod original ("$trimmedName"). Se procederá a inspección GATT del servicio 01FF0100.';
    } else if (hasNxpTripperUuid || (hasNameMatch && hasKnownSerialUuid)) {
      isCandidate = true;
      confidence = 'Alta';
      evidence =
          'Nombre anunciado concordante ("$trimmedName") y servicios de comunicación serie NXP detectados.';
    } else if (hasNameMatch) {
      isCandidate = true;
      confidence = 'Media';
      evidence =
          'Nombre concordante con Royal Enfield ("$trimmedName"). Se requiere conectar para inspeccionar servicios GATT.';
    } else if (hasKnownSerialUuid || hasNxpMac) {
      confidence = 'Baja';
      evidence = cleanName.isNotEmpty
          ? 'Perfil serie/NXP detectado pero nombre ("$trimmedName") no asociado a Royal Enfield.'
          : 'Perfil serie/NXP detectado en dispositivo sin nombre anunciado.';
    } else if (cleanName.isEmpty) {
      evidence =
          'Periférico BLE transmitiendo paquetes publicitarios sin nombre.';
    } else {
      evidence =
          'Dispositivo BLE genérico sin identificadores de Royal Enfield.';
    }

    final effectiveName = trimmedName.isEmpty
        ? 'Dispositivo BLE sin nombre'
        : trimmedName;
    final effectiveId = id.trim().isEmpty ? 'ID no disponible' : id.trim();

    return TripperDevice(
      id: effectiveId,
      name: effectiveName,
      rssi: rssi,
      serviceUuids: serviceUuids,
      manufacturerData: manufacturerData,
      isTripperCandidate: isCandidate,
      confidenceLevel: confidence,
      technicalEvidence: evidence,
    );
  }

  /// Crea una copia de este [TripperDevice] actualizando los campos especificados.
  TripperDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    List<String>? serviceUuids,
    Map<int, List<int>>? manufacturerData,
    bool? isTripperCandidate,
    String? confidenceLevel,
    String? technicalEvidence,
  }) {
    return TripperDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      manufacturerData: manufacturerData ?? this.manufacturerData,
      isTripperCandidate: isTripperCandidate ?? this.isTripperCandidate,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      technicalEvidence: technicalEvidence ?? this.technicalEvidence,
    );
  }
}
