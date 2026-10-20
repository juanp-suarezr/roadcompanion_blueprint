import 'package:flutter/widgets.dart';

import '../../domain/entities/imported_gpx_route.dart';
import '../../domain/entities/saved_route_metadata.dart';
import '../../domain/repositories/gpx_route_repository.dart';
import '../../infrastructure/repositories/local_gpx_route_repository.dart';
import '../../infrastructure/services/gpx_import_service.dart';

/// Notificador de estado para rutas GPX importadas y persistidas en almacenamiento local.
///
/// Gestiona la biblioteca de rutas guardadas, la ruta actualmente activa en memoria
/// y los estados de carga y error durante la navegación entre pantallas.
class ImportedRouteState extends ChangeNotifier {
  final GpxImportService _importService;
  final GpxRouteRepository _repository;

  ImportedGpxRoute? _currentRoute;
  List<SavedRouteMetadata> _savedRoutes = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  ImportedRouteState({
    GpxImportService? importService,
    GpxRouteRepository? repository,
  }) : _importService = importService ?? GpxImportService(),
       _repository = repository ?? LocalGpxRouteRepository() {
    loadSavedRoutes();
  }

  /// Ruta GPX actualmente cargada y lista para seguimiento o visualización.
  ImportedGpxRoute? get currentRoute => _currentRoute;

  /// Biblioteca de rutas GPX guardadas en el almacenamiento privado de la app.
  List<SavedRouteMetadata> get savedRoutes => List.unmodifiable(_savedRoutes);

  /// Indica si existe una ruta activa en memoria.
  bool get hasRoute => _currentRoute != null;

  /// Indica si hay una operación de importación o lectura de disco en progreso.
  bool get isLoading => _isLoading;

  /// Mensaje de error descriptivo en caso de fallo.
  String? get errorMessage => _errorMessage;

  /// Mensaje informativo contextual.
  String? get infoMessage => _infoMessage;

  /// Carga la lista de metadatos de rutas guardadas en el disco privado.
  Future<void> loadSavedRoutes() async {
    try {
      _savedRoutes = await _repository.getSavedRoutes();
      notifyListeners();
    } catch (_) {
      // Manejar silenciosamente si aún no hay directorio creado
    }
  }

  /// Ejecuta el selector de archivos, valida y persiste la nueva ruta GPX.
  Future<bool> importGpxRoute() async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _importService.importGpx();
      _isLoading = false;

      switch (result) {
        case GpxImportSuccess(:final route, :final fileName, :final rawContent):
          _currentRoute = route;
          _errorMessage = null;

          // Guardar persistentemente en el almacenamiento local
          if (rawContent.isNotEmpty) {
            try {
              await _repository.saveRoute(
                originalFileName: fileName,
                rawGpxContent: rawContent,
                parsedRoute: route,
              );
              await loadSavedRoutes();
            } catch (_) {}
          }

          _infoMessage =
              'Ruta "${route.name}" importada exitosamente (${route.totalPoints} puntos).';
          notifyListeners();
          return true;

        case GpxImportCancelled():
          _infoMessage = 'Selección de archivo cancelada.';
          notifyListeners();
          return false;

        case GpxImportFailure(:final message):
          _errorMessage = message;
          notifyListeners();
          return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Ocurrió un error inesperado al importar la ruta: $e';
      notifyListeners();
      return false;
    }
  }

  /// Carga y selecciona una ruta previamente guardada a partir de su [id].
  Future<bool> selectSavedRoute(String id) async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final route = await _repository.loadRoute(id);
      _currentRoute = route;
      _isLoading = false;
      _infoMessage = 'Ruta "${route.name}" cargada desde la biblioteca.';
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'No se pudo cargar la ruta seleccionada: $e';
      await loadSavedRoutes(); // Actualizar índice por si el archivo fue borrado
      notifyListeners();
      return false;
    }
  }

  /// Elimina una ruta guardada en disco.
  Future<void> deleteSavedRoute(String id) async {
    try {
      await _repository.deleteRoute(id);
      if (_currentRoute != null &&
          _savedRoutes.any(
            (r) => r.id == id && r.name == _currentRoute!.name,
          )) {
        _currentRoute = null;
      }
      await loadSavedRoutes();
      _infoMessage = 'Ruta eliminada de la biblioteca.';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'No se pudo eliminar la ruta: $e';
      notifyListeners();
    }
  }

  /// Establece manualmente una ruta importada (útil para pruebas o adaptadores).
  void setRoute(ImportedGpxRoute route) {
    _currentRoute = route;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  /// Retira la ruta activa de memoria y regresa al modo de demostración.
  void clearRoute() {
    _currentRoute = null;
    _errorMessage = null;
    _infoMessage = 'Se ha retirado la ruta GPX. Regresando a la demostración.';
    notifyListeners();
  }

  /// Limpia los mensajes informativos o de error.
  void clearMessages() {
    if (_errorMessage != null || _infoMessage != null) {
      _errorMessage = null;
      _infoMessage = null;
      notifyListeners();
    }
  }
}

/// InheritedWidget para exponer [ImportedRouteState] reactivamente en el árbol de widgets.
class ImportedRouteScope extends InheritedNotifier<ImportedRouteState> {
  const ImportedRouteScope({
    super.key,
    required ImportedRouteState routeState,
    required super.child,
  }) : super(notifier: routeState);

  static ImportedRouteState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ImportedRouteScope>();
    assert(
      scope != null,
      'No se encontró un ImportedRouteScope en el contexto de widgets proporcionado.',
    );
    return scope!.notifier!;
  }

  static ImportedRouteState? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ImportedRouteScope>();
    return scope?.notifier;
  }
}
