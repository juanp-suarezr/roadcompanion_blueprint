import '../entities/gps_position.dart';

/// Resultado de la verificación o solicitud de permisos de ubicación.
enum LocationPermissionResult {
  /// Permiso otorgado (en primer plano).
  granted,

  /// Permiso denegado por el usuario (puede volver a solicitarse).
  denied,

  /// Permiso denegado permanentemente (requiere ir a Ajustes del sistema).
  deniedForever,

  /// El servicio de ubicación / antena GPS del dispositivo se encuentra apagado.
  serviceDisabled,
}

/// Contrato abstracto para el servicio de geolocalización y telemetría GPS.
///
/// Permite simular lecturas en pruebas automatizadas y desacoplar la aplicación
/// de las APIs nativas de Android.
abstract class LocationService {
  /// Comprueba si el sensor/servicio de ubicación del dispositivo está encendido.
  Future<bool> isLocationServiceEnabled();

  /// Comprueba el estado actual de los permisos de ubicación en primer plano.
  Future<LocationPermissionResult> checkPermission();

  /// Solicita al usuario los permisos de ubicación en primer plano.
  Future<LocationPermissionResult> requestPermission();

  /// Comprueba si se cuenta con permiso de ubicación en segundo plano.
  Future<bool> checkBackgroundPermission() async => false;

  /// Solicita de forma progresiva el permiso de ubicación en segundo plano.
  Future<LocationPermissionResult> requestBackgroundPermission() async =>
      LocationPermissionResult.denied;

  /// Flujo continuo de posiciones GPS con alta precisión para navegación.
  ///
  /// Si [enableBackgroundNotification] es verdadero, en plataformas compatibles (Android)
  /// se iniciará un Foreground Service con notificación persistente para mantener el
  /// seguimiento activo aún con la pantalla apagada.
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
    bool enableBackgroundNotification = false,
    String? notificationTitle,
    String? notificationText,
  });

  /// Obtiene una lectura puntual de posición GPS del dispositivo con validación de precisión.
  ///
  /// Retorna `null` si el sensor está apagado, no hay permisos o no se obtiene lectura en [timeLimit].
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;
}
