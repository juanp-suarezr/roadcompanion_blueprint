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

  /// Flujo continuo de posiciones GPS en primer plano con alta precisión para navegación.
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
  });
}
