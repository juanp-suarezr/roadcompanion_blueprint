/// Contrato de comunicación para pantallas externas y pods de navegación (ej. Tripper Pod).
abstract class ExternalDisplayGateway {
  /// Indica si existe una pantalla externa enlazada y conectada activamente.
  bool get isConnected;

  /// Nombre del dispositivo conectado o null si no hay conexión.
  String? get connectedDeviceName;

  /// Envía métricas de navegación actualizadas a la pantalla externa.
  Future<void> sendNavigationUpdate({
    required double distanceToManeuverMeters,
    required String maneuverIconCode,
    required String streetName,
    required double progressPercentage,
  });
}

/// Implementación no operativa segura (No-Op) para la versión visual inicial.
///
/// Aísla completamente la aplicación de búsquedas Bluetooth BLE, emparejamientos
/// y comandos a hardware, asegurando que no se ejecuten operaciones de radio ni permisos.
class NoOpExternalDisplayGateway implements ExternalDisplayGateway {
  const NoOpExternalDisplayGateway();

  @override
  bool get isConnected => false;

  @override
  String? get connectedDeviceName => null;

  @override
  Future<void> sendNavigationUpdate({
    required double distanceToManeuverMeters,
    required String maneuverIconCode,
    required String streetName,
    required double progressPercentage,
  }) async {
    // No-Op intencional: la integración Bluetooth BLE pertenece a fases posteriores
  }
}
