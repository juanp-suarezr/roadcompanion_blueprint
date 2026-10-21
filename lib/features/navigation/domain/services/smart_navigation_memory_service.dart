import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../domain/entities/coordinates.dart';
import '../entities/access_restriction.dart';
import '../entities/navigation_issue_report.dart';
import '../entities/saved_favorite_route.dart';

/// Servicio de memoria inteligente local y persistente para REstelar.
///
/// Gestiona rutas favoritas y reportes viales del motociclista (portones cerrados, giros prohibidos,
/// vías destapadas, baches severos), sincronizándolos automáticamente con el motor de enrutamiento
/// y el validador de restricciones para influir en los cálculos futuros.
class SmartNavigationMemoryService {
  static const String _keyFavorites = 'rc_smart_favorite_routes';
  static const String _keyReports = 'rc_smart_navigation_reports';

  final SharedPreferences? _prefs;

  // Caché en memoria para acceso sincrónico rápido y soporte para pruebas unitarias sin plugins
  final List<SavedFavoriteRoute> _inMemoryFavorites = [];
  final List<NavigationIssueReport> _inMemoryReports = [];
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  SmartNavigationMemoryService([this._prefs]);

  /// Crea una instancia conectada a las [SharedPreferences] reales del dispositivo.
  static Future<SmartNavigationMemoryService> create() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = SmartNavigationMemoryService(prefs);
      await service.load();
      return service;
    } catch (_) {
      final fallback = SmartNavigationMemoryService(null);
      await fallback.load();
      return fallback;
    }
  }

  /// Carga datos guardados desde el almacenamiento local persistente a la memoria.
  Future<void> load() async {
    _inMemoryFavorites.clear();
    _inMemoryReports.clear();

    if (_prefs != null) {
      final rawFavs = _prefs.getStringList(_keyFavorites) ?? [];
      for (final raw in rawFavs) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _inMemoryFavorites.add(SavedFavoriteRoute.fromJson(map));
        } catch (_) {}
      }

      final rawReps = _prefs.getStringList(_keyReports) ?? [];
      for (final raw in rawReps) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _inMemoryReports.add(NavigationIssueReport.fromJson(map));
        } catch (_) {}
      }
    }

    _isLoaded = true;
  }

  // --- SECCIÓN: RUTAS FAVORITAS ---

  /// Obtiene la lista de rutas favoritas guardadas, ordenadas de más reciente a más antigua.
  List<SavedFavoriteRoute> get favoriteRoutes {
    final list = List<SavedFavoriteRoute>.from(_inMemoryFavorites);
    list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(list);
  }

  /// Guarda una nueva ruta favorita en la memoria persistente.
  Future<void> saveFavoriteRoute(SavedFavoriteRoute route) async {
    _inMemoryFavorites.removeWhere((r) => r.id == route.id);
    _inMemoryFavorites.add(route);
    await _persistFavorites();
  }

  /// Elimina una ruta favorita por su identificador.
  Future<void> deleteFavoriteRoute(String id) async {
    _inMemoryFavorites.removeWhere((r) => r.id == id);
    await _persistFavorites();
  }

  Future<void> _persistFavorites() async {
    if (_prefs == null) return;
    final list = _inMemoryFavorites.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_keyFavorites, list);
  }

  // --- SECCIÓN: REPORTES VIALES ---

  /// Obtiene todos los reportes viales guardados en la memoria inteligente.
  List<NavigationIssueReport> get reports {
    final list = List<NavigationIssueReport>.from(_inMemoryReports);
    list.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    return List.unmodifiable(list);
  }

  /// Agrega un nuevo reporte de navegación a la memoria local.
  Future<void> addReport(NavigationIssueReport report) async {
    // Evitar reportes idénticos duplicados en el mismo sector (< 25 m y mismo tipo)
    _inMemoryReports.removeWhere((existing) =>
        existing.type == report.type &&
        existing.location.distanceTo(report.location) < 25.0);

    _inMemoryReports.add(report);
    await _persistReports();
  }

  /// Actualiza el estado de verificación de un reporte (confirmado, pendiente o descartado).
  Future<void> updateReportStatus(
    String id,
    ReportVerificationStatus newStatus,
  ) async {
    final index = _inMemoryReports.indexWhere((r) => r.id == id);
    if (index != -1) {
      _inMemoryReports[index] = _inMemoryReports[index].copyWith(status: newStatus);
      await _persistReports();
    }
  }

  /// Elimina un reporte vial guardado.
  Future<void> deleteReport(String id) async {
    _inMemoryReports.removeWhere((r) => r.id == id);
    await _persistReports();
  }

  /// Elimina toda la información guardada por el usuario (rutas favoritas y reportes).
  Future<void> clearAllUserMemory() async {
    _inMemoryFavorites.clear();
    _inMemoryReports.clear();
    if (_prefs != null) {
      await _prefs.remove(_keyFavorites);
      await _prefs.remove(_keyReports);
    }
  }

  Future<void> _persistReports() async {
    if (_prefs == null) return;
    final list = _inMemoryReports.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_keyReports, list);
  }

  // --- SECCIÓN: APLICACIÓN DE LA MEMORIA EN EL ENRUTAMIENTO ---

  /// Sincroniza los reportes confirmados del usuario con el registro territorial de restricciones.
  ///
  /// Transforma portones privados y destinos inaccesibles confirmados en registros de restricción
  /// para que el motor de rutas desvíe automáticamente el tramo y seleccione una alternativa pública.
  void syncWithRestrictionRegistry(RoadAccessRestrictionRegistry registry) {
    for (final report in _inMemoryReports) {
      if (report.status == ReportVerificationStatus.confirmed) {
        final record = report.toRestrictionRecord();
        if (record != null) {
          registry.addRecord(record);
        }
      }
    }
  }

  /// Detecta si una geometría vial calculada pasa cerca de reportes registrados por el usuario.
  List<NavigationIssueReport> checkReportsAlongRoute(
    List<Coordinates> geometry, {
    double thresholdMeters = 35.0,
  }) {
    final matchingReports = <NavigationIssueReport>[];

    for (final rep in _inMemoryReports) {
      if (rep.status == ReportVerificationStatus.dismissed) {
        continue;
      }
      for (final pt in geometry) {
        if (pt.distanceTo(rep.location) <= thresholdMeters) {
          matchingReports.add(rep);
          break;
        }
      }
    }

    return matchingReports;
  }
}
