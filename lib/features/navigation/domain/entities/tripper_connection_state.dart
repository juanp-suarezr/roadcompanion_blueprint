/// Estados granulares del ciclo de vida de la conexión Bluetooth LE con el Royal Enfield Tripper Pod.
///
/// Diferencia explícitamente cada etapa física según el protocolo NXP / WazeTripper:
/// desde el escaneo hasta el descubrimiento GATT, autenticación y confirmación de transmisión.
enum TripperConnectionState {
  /// Antena inactiva o sin operaciones BLE en curso.
  idle,

  /// Bluetooth apagado en el sistema operativo Android.
  bluetoothDisabled,

  /// Permisos de Bluetooth (Nearby Devices en Android 12+) o ubicación denegados.
  permissionDenied,

  /// Alias de compatibilidad para permisos pendientes de autorización.
  permissionRequired,

  /// Escaneando activamente dispositivos BLE en el entorno.
  scanning,

  /// Dispositivo candidato RE_DISP detectado en el entorno.
  deviceFound,

  /// Solicitando enlace GATT con el periférico.
  connecting,

  /// Capa física GATT conectada con éxito.
  gattConnected,

  /// Servicios GATT descubiertos e inspeccionados.
  servicesDiscovered,

  /// Característica de comunicación NXP Wireless UART identificada.
  characteristicIdentified,

  /// Autenticación pendiente (esperando PIN del tablero o confirmación de handshake).
  authPending,

  /// Autenticado con éxito y sesión BLE activa en el Tripper Pod.
  authenticated,

  /// Comunicación bidireccional verificada mediante intercambio GATT.
  bidirectionalVerified,

  /// Envío de mensaje de prueba (keepalive, hora o maniobra) confirmado en hardware.
  testMessageSent,

  /// Estado de compatibilidad: sesión completamente operativa.
  connected,

  /// Desconectando enlace BLE de forma segura.
  disconnecting,

  /// Desconectado o enlace finalizado.
  disconnected,

  /// Error de conexión, timeout GATT (código 147) o fallo de enlace.
  error;

  /// Nombre técnico y descriptivo en español para interfaces y registros de diagnóstico.
  String get displayName {
    switch (this) {
      case TripperConnectionState.idle:
        return 'Inactivo';
      case TripperConnectionState.bluetoothDisabled:
        return 'Bluetooth apagado';
      case TripperConnectionState.permissionDenied:
      case TripperConnectionState.permissionRequired:
        return 'Permiso denegado';
      case TripperConnectionState.scanning:
        return 'Buscando dispositivos';
      case TripperConnectionState.deviceFound:
        return 'Tripper detectado';
      case TripperConnectionState.connecting:
        return 'Conectando';
      case TripperConnectionState.gattConnected:
        return 'GATT conectado';
      case TripperConnectionState.servicesDiscovered:
        return 'Servicios descubiertos';
      case TripperConnectionState.characteristicIdentified:
        return 'Característica de comunicación identificada';
      case TripperConnectionState.authPending:
        return 'Autenticación pendiente';
      case TripperConnectionState.authenticated:
        return 'Autenticado';
      case TripperConnectionState.bidirectionalVerified:
        return 'Comunicación bidireccional verificada';
      case TripperConnectionState.testMessageSent:
        return 'Envío de mensaje de prueba confirmado';
      case TripperConnectionState.connected:
        return 'Conectado';
      case TripperConnectionState.disconnecting:
        return 'Desconectando';
      case TripperConnectionState.disconnected:
        return 'Desconectado';
      case TripperConnectionState.error:
        return 'Error de conexión';
    }
  }

  /// Indica si la sesión está en un estado completamente validado para transmitir navegación.
  bool get isReadyForNavigation =>
      this == TripperConnectionState.authenticated ||
      this == TripperConnectionState.bidirectionalVerified ||
      this == TripperConnectionState.testMessageSent ||
      this == TripperConnectionState.connected;
}
