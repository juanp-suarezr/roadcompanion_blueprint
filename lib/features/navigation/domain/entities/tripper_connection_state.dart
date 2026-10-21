/// Estados del ciclo de vida de la conexión Bluetooth LE con el Tripper Pod.
enum TripperConnectionState {
  /// Antena inactiva o sin operaciones BLE en curso.
  idle,

  /// Bluetooth apagado en el sistema operativo.
  bluetoothDisabled,

  /// Permisos de Bluetooth o ubicación pendientes de autorización.
  permissionRequired,

  /// Escaneando activamente dispositivos BLE cercanos.
  scanning,

  /// Dispositivo candidato detectado en el entorno.
  deviceFound,

  /// Estableciendo enlace GATT con el dispositivo.
  connecting,

  /// Conexión BLE establecida y servicios descubiertos.
  connected,

  /// Desconectando de forma segura.
  disconnecting,

  /// Error de conexión, tiempo de espera agotado o enlace rechazado.
  error,
}
