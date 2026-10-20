import '../entities/navigation_session.dart';

/// Contrato para el almacenamiento y consulta de sesiones de seguimiento.
abstract class SessionRepository {
  /// Obtiene la lista de sesiones de navegación registradas.
  Future<List<NavigationSession>> getSessions();

  /// Guarda una nueva sesión completada o interrumpida.
  Future<void> saveSession(NavigationSession session);

  /// Elimina una sesión por su [id].
  Future<void> deleteSession(String id);
}
