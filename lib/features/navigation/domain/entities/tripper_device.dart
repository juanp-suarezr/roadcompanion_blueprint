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
    required List<String> serviceUuids,
    Map<int, List<int>> manufacturerData = const {},
  }) {
    final cleanName = name.trim().toUpperCase();
    final bool hasNameMatch = cleanName.contains('ROYAL') ||
        cleanName.contains('ENFIELD') ||
        cleanName.contains('TRIPPER') ||
        cleanName.contains('RE_') ||
        cleanName.contains('METEOR');

    // UUIDs comunes en módulos UART/Serie o referencias de la industria
    final bool hasKnownSerialUuid = serviceUuids.any((u) {
      final norm = u.toLowerCase();
      return norm.contains('ffe0') ||
          norm.contains('fff0') ||
          norm.contains('fe95') ||
          norm.contains('1800') ||
          norm.contains('180a');
    });

    bool isCandidate = false;
    String confidence = 'Baja';
    String evidence = 'Dispositivo BLE genérico sin identificadores de Royal Enfield.';

    if (hasNameMatch && hasKnownSerialUuid) {
      isCandidate = true;
      confidence = 'Alta';
      evidence =
          'Nombre anunciado concordante ("$name") y servicios de comunicación serie detectados.';
    } else if (hasNameMatch) {
      isCandidate = true;
      confidence = 'Media';
      evidence =
          'Nombre concordante con Royal Enfield ("$name"). Se requiere conectar para inspeccionar servicios GATT.';
    } else if (hasKnownSerialUuid && cleanName.isNotEmpty) {
      confidence = 'Baja';
      evidence =
          'Perfil serie genérico pero nombre ("$name") no asociado a Royal Enfield.';
    }

    return TripperDevice(
      id: id,
      name: name.isEmpty ? 'Dispositivo BLE sin nombre' : name,
      rssi: rssi,
      serviceUuids: serviceUuids,
      manufacturerData: manufacturerData,
      isTripperCandidate: isCandidate,
      confidenceLevel: confidence,
      technicalEvidence: evidence,
    );
  }
}
