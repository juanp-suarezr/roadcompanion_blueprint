import 'dart:async';

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../bridge/domain/entities/bridge_instruction_status.dart';
import '../../../bridge/domain/entities/bridge_navigation_instruction.dart';
import '../../../bridge/domain/entities/bridge_source_type.dart';
import '../../../bridge/domain/services/navigation_instruction_parser.dart';
import '../entities/road_curvature.dart';
import '../entities/tripper_connection_state.dart';
import 'road_curvature_estimator.dart';
import 'tripper_ble_service.dart';

/// Fuente de navegación principal seleccionada por el usuario para el viaje.
enum SelectedNavigationSourceType {
  /// Navegador interno de RoadCompanion (OSRM + GPX + geometría vial verificada).
  internal,

  /// Waze (`com.waze`) mediante captura de notificaciones del sistema Android.
  waze,

  /// Google Maps (`com.google.android.apps.maps`) mediante captura de notificaciones.
  googleMaps;

  String get displayName {
    switch (this) {
      case SelectedNavigationSourceType.internal:
        return 'RoadCompanion Interno';
      case SelectedNavigationSourceType.waze:
        return 'Waze';
      case SelectedNavigationSourceType.googleMaps:
        return 'Google Maps';
    }
  }

  String? get androidPackageName {
    switch (this) {
      case SelectedNavigationSourceType.internal:
        return 'none';
      case SelectedNavigationSourceType.waze:
        return 'com.waze';
      case SelectedNavigationSourceType.googleMaps:
        return 'com.google.android.apps.maps';
    }
  }

  BridgeSourceType? get bridgeSourceType {
    switch (this) {
      case SelectedNavigationSourceType.internal:
        return null;
      case SelectedNavigationSourceType.waze:
        return BridgeSourceType.waze;
      case SelectedNavigationSourceType.googleMaps:
        return BridgeSourceType.googleMaps;
    }
  }

  static SelectedNavigationSourceType fromStorageKey(String? raw) {
    switch (raw) {
      case 'waze':
        return SelectedNavigationSourceType.waze;
      case 'googleMaps':
        return SelectedNavigationSourceType.googleMaps;
      case 'internal':
      default:
        return SelectedNavigationSourceType.internal;
    }
  }
}

/// Declaración explícita de capacidades y limitaciones reales de cada fuente.
class NavigationSourceCapabilities {
  final bool providesManeuvers;
  final bool providesDistances;
  final bool providesRoadGeometry;
  final bool supportsRealCurveDetection;
  final bool requiresNotificationAccess;
  final String limitationDisclosure;

  const NavigationSourceCapabilities({
    required this.providesManeuvers,
    required this.providesDistances,
    required this.providesRoadGeometry,
    required this.supportsRealCurveDetection,
    required this.requiresNotificationAccess,
    required this.limitationDisclosure,
  });
}

/// Estados explícitos de la máquina de estados de navegación y BLE (Sección 9).
enum CompanionNavigationState {
  idle,
  awaitingPermission,
  sourceSelected,
  navigationDetected,
  navigationActive,
  navigationStale,
  navigationStopped,
  bleConnecting,
  bleConnected,
  bleDisconnected,
  recovering;

  String get displayName {
    switch (this) {
      case CompanionNavigationState.idle:
        return 'Inactivo';
      case CompanionNavigationState.awaitingPermission:
        return 'Esperando permiso de notificaciones';
      case CompanionNavigationState.sourceSelected:
        return 'Fuente seleccionada (sin ruta activa)';
      case CompanionNavigationState.navigationDetected:
        return 'Notificación detectada (validando maniobra)';
      case CompanionNavigationState.navigationActive:
        return 'Navegación activa sincronizada';
      case CompanionNavigationState.navigationStale:
        return 'Navegación desactualizada / sin señal reciente';
      case CompanionNavigationState.navigationStopped:
        return 'Navegación finalizada';
      case CompanionNavigationState.bleConnecting:
        return 'Conectando BLE con Tripper Pod';
      case CompanionNavigationState.bleConnected:
        return 'Tripper Pod conectado';
      case CompanionNavigationState.bleDisconnected:
        return 'Tripper Pod desconectado';
      case CompanionNavigationState.recovering:
        return 'Recuperando estado de navegación';
    }
  }
}

/// Interfaz común para todas las fuentes de navegación de RoadCompanion Blue.
abstract class NavigationSource {
  SelectedNavigationSourceType get sourceType;
  NavigationSourceCapabilities get capabilities;

  /// Evalúa la curvatura vial únicamente si la fuente provee geometría cuya
  /// correspondencia con la ruta activa está verificada.
  RoadCurvatureInfo evaluateCurvature({
    List<Coordinates> geometry = const [],
    double traveledDistanceMeters = 0.0,
    List<Maneuver> maneuvers = const [],
    int routeVersion = 1,
  });
}

/// Fuente de navegación interna con geometría vial OSRM / GPX verificada.
class InternalNavigationSource implements NavigationSource {
  const InternalNavigationSource();

  @override
  SelectedNavigationSourceType get sourceType =>
      SelectedNavigationSourceType.internal;

  @override
  NavigationSourceCapabilities get capabilities =>
      const NavigationSourceCapabilities(
        providesManeuvers: true,
        providesDistances: true,
        providesRoadGeometry: true,
        supportsRealCurveDetection: true,
        requiresNotificationAccess: false,
        limitationDisclosure:
            'Provee maniobras, distancias y geometría vial verificada (OSRM/GPX) para detección anticipada de curvas.',
      );

  @override
  RoadCurvatureInfo evaluateCurvature({
    List<Coordinates> geometry = const [],
    double traveledDistanceMeters = 0.0,
    List<Maneuver> maneuvers = const [],
    int routeVersion = 1,
  }) {
    if (geometry.length < 3) {
      return RoadCurvatureInfo.insufficient(
        geometrySource: GeometrySource.internalRouteOsrm,
        routeVersion: routeVersion,
      );
    }
    return RoadCurvatureEstimator.estimate(
      geometry: geometry,
      traveledDistanceMeters: traveledDistanceMeters,
      maneuvers: maneuvers,
      geometrySource: GeometrySource.internalRouteOsrm,
      routeVersion: routeVersion,
    );
  }
}

/// Fuente de navegación externa para Waze (`com.waze`) independiente de Google Maps.
class WazeNavigationSource implements NavigationSource {
  final NavigationInstructionParser _parser;

  const WazeNavigationSource({
    NavigationInstructionParser parser = const NavigationInstructionParser(),
  }) : _parser = parser;

  @override
  SelectedNavigationSourceType get sourceType =>
      SelectedNavigationSourceType.waze;

  @override
  NavigationSourceCapabilities get capabilities =>
      const NavigationSourceCapabilities(
        providesManeuvers: true,
        providesDistances: true,
        providesRoadGeometry: false,
        supportsRealCurveDetection: false,
        requiresNotificationAccess: true,
        limitationDisclosure:
            'Waze expone giro y distancia en su notificación de Android, pero NO expone la polilínea activa. La detección geométrica de curvas permanece en estado de geometría no expuesta para no inventar curvas.',
      );

  BridgeNavigationInstruction parseNotification({
    String? title,
    String? text,
    String? subText,
    DateTime? timestamp,
    bool isRemoved = false,
  }) {
    final ts = timestamp ?? DateTime.now();
    if (isRemoved) {
      return BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.unknown,
        rawText: '',
        receivedAt: ts,
        status: BridgeInstructionStatus.stale,
      );
    }
    return _parser.parseWaze(
      rawTitle: title,
      rawText: text,
      rawSubText: subText,
      receivedAt: ts,
    );
  }

  @override
  RoadCurvatureInfo evaluateCurvature({
    List<Coordinates> geometry = const [],
    double traveledDistanceMeters = 0.0,
    List<Maneuver> maneuvers = const [],
    int routeVersion = 1,
  }) {
    // Regla obligatoria (Sección 8): No asumir que la ruta activa de Waze coincide
    // con una ruta interna no verificada. Declarar explícitamente información insuficiente.
    return RoadCurvatureInfo.insufficient(
      geometrySource: GeometrySource.none,
      routeVersion: routeVersion,
    );
  }
}

/// Fuente de navegación externa para Google Maps (`com.google.android.apps.maps`)
/// independiente de Waze.
class GoogleMapsNavigationSource implements NavigationSource {
  final NavigationInstructionParser _parser;

  const GoogleMapsNavigationSource({
    NavigationInstructionParser parser = const NavigationInstructionParser(),
  }) : _parser = parser;

  @override
  SelectedNavigationSourceType get sourceType =>
      SelectedNavigationSourceType.googleMaps;

  @override
  NavigationSourceCapabilities get capabilities =>
      const NavigationSourceCapabilities(
        providesManeuvers: true,
        providesDistances: true,
        providesRoadGeometry: false,
        supportsRealCurveDetection: false,
        requiresNotificationAccess: true,
        limitationDisclosure:
            'Google Maps expone maniobras y distancias en su notificación turn-by-turn, pero NO expone la polilínea de la ruta activa. No se inventan curvas cuando no existe geometría verificada.',
      );

  BridgeNavigationInstruction parseNotification({
    String? title,
    String? text,
    String? subText,
    DateTime? timestamp,
    bool isRemoved = false,
  }) {
    final ts = timestamp ?? DateTime.now();
    if (isRemoved) {
      return BridgeNavigationInstruction(
        source: BridgeSourceType.googleMaps,
        maneuverType: ManeuverType.unknown,
        rawText: '',
        receivedAt: ts,
        status: BridgeInstructionStatus.stale,
      );
    }
    return _parser.parseGoogleMaps(
      rawTitle: title,
      rawText: text,
      rawSubText: subText,
      receivedAt: ts,
    );
  }

  @override
  RoadCurvatureInfo evaluateCurvature({
    List<Coordinates> geometry = const [],
    double traveledDistanceMeters = 0.0,
    List<Maneuver> maneuvers = const [],
    int routeVersion = 1,
  }) {
    return RoadCurvatureInfo.insufficient(
      geometrySource: GeometrySource.none,
      routeVersion: routeVersion,
    );
  }
}

/// Máquina de estados explícita de navegación y sincronización BLE (Sección 9).
///
/// Garantiza las 6 reglas críticas:
/// 1. Seleccionar una fuente NO equivale a tener una ruta activa (`sourceSelected`).
/// 2. Recibir una notificación NO equivale a tener una maniobra válida (`navigationDetected` vs `navigationActive`).
/// 3. Finalizar la ruta o eliminar la notificación cancela la instrucción activa (`navigationStopped` / `navigationStale`).
/// 4. No enviar instrucciones ficticias al Tripper cuando no hay navegación válida.
/// 5. Si el Tripper se desconecta por inactividad (watchdog), reflejar `bleDisconnected` sin bucle agresivo.
/// 6. Cambiar la fuente de navegación invalida inmediatamente los datos de la fuente anterior.
class CompanionNavigationStateMachine {
  final TripperBleService? _bleService;
  NavigationSource _activeSource;
  CompanionNavigationState _state = CompanionNavigationState.idle;
  BridgeNavigationInstruction? _activeExternalInstruction;
  RoadCurvatureInfo _curvatureInfo = RoadCurvatureInfo.insufficient();
  bool _hasNotificationPermission = false;
  int _routeVersion = 1;

  CompanionNavigationStateMachine({
    NavigationSource initialSource = const InternalNavigationSource(),
    TripperBleService? bleService,
    bool hasNotificationPermission = false,
  }) : _activeSource = initialSource,
       _bleService = bleService,
       _hasNotificationPermission = hasNotificationPermission {
    _recomputeStateAfterSelection();
  }

  NavigationSource get activeSource => _activeSource;
  SelectedNavigationSourceType get selectedSourceType =>
      _activeSource.sourceType;
  NavigationSourceCapabilities get capabilities => _activeSource.capabilities;
  CompanionNavigationState get state => _state;
  BridgeNavigationInstruction? get activeExternalInstruction =>
      _activeExternalInstruction;
  RoadCurvatureInfo get curvatureInfo => _curvatureInfo;
  bool get hasNotificationPermission => _hasNotificationPermission;
  int get routeVersion => _routeVersion;

  /// Selecciona una nueva fuente de navegación e invalida cualquier estado de la fuente anterior (Regla 1 y Regla 6).
  Future<void> selectSource(
    SelectedNavigationSourceType type, {
    bool? notificationPermissionGranted,
  }) async {
    if (notificationPermissionGranted != null) {
      _hasNotificationPermission = notificationPermissionGranted;
    }

    final changed = _activeSource.sourceType != type;
    _activeSource = switch (type) {
      SelectedNavigationSourceType.internal => const InternalNavigationSource(),
      SelectedNavigationSourceType.waze => const WazeNavigationSource(),
      SelectedNavigationSourceType.googleMaps =>
        const GoogleMapsNavigationSource(),
    };

    if (changed) {
      _routeVersion++;
      _activeExternalInstruction = null;
      _curvatureInfo = _activeSource.evaluateCurvature(
        routeVersion: _routeVersion,
      );
      _bleService?.clearActiveNavPacket(
        reason: 'Cambio de fuente de navegación a ${type.displayName}',
      );
      if (_bleService != null &&
          _bleService.currentState.isReadyForNavigation) {
        await _bleService.stopNavigation();
      }
    }

    _recomputeStateAfterSelection();
  }

  /// Actualiza el estado del permiso de acceso a notificaciones (ej. al volver de Ajustes de Android).
  void updateNotificationPermission(bool granted) {
    _hasNotificationPermission = granted;
    if (_activeSource.capabilities.requiresNotificationAccess) {
      if (!granted) {
        _state = CompanionNavigationState.awaitingPermission;
      } else if (_state == CompanionNavigationState.awaitingPermission) {
        _state = CompanionNavigationState.sourceSelected;
      }
    }
  }

  /// Procesa una instrucción proveniente de la fuente externa activa.
  Future<void> onExternalInstruction(
    BridgeNavigationInstruction instruction,
  ) async {
    // Ignorar eventos que no correspondan a la fuente seleccionada
    final expectedBridgeSource = _activeSource.sourceType.bridgeSourceType;
    if (expectedBridgeSource == null ||
        instruction.source != expectedBridgeSource) {
      return;
    }

    // Regla 3: si la notificación fue eliminada o expiró, cancelar instrucción activa
    if (instruction.status == BridgeInstructionStatus.stale) {
      _activeExternalInstruction = instruction;
      _state = CompanionNavigationState.navigationStopped;
      _bleService?.clearActiveNavPacket(
        reason: 'Fin o eliminación de notificación externa',
      );
      if (_bleService != null &&
          _bleService.currentState.isReadyForNavigation) {
        await _bleService.stopNavigation();
      }
      return;
    }

    // Regla 2: recibir una notificación no equivale a tener una maniobra válida
    _activeExternalInstruction = instruction;
    if (instruction.isCompatibleWithTripper) {
      _state = CompanionNavigationState.navigationActive;
    } else {
      _state = CompanionNavigationState.navigationDetected;
    }
  }

  /// Marca la navegación actual como desactualizada por timeout sin nuevas actualizaciones.
  Future<void> markNavigationStale() async {
    if (_activeExternalInstruction != null) {
      _activeExternalInstruction = _activeExternalInstruction!.asStale();
    }
    _state = CompanionNavigationState.navigationStale;
    _bleService?.clearActiveNavPacket(
      reason: 'Instrucción de navegación desactualizada (stale)',
    );
  }

  /// Detiene explícitamente la navegación activa (Regla 3 y Regla 4).
  Future<void> stopNavigation() async {
    _activeExternalInstruction = null;
    _curvatureInfo = _activeSource.evaluateCurvature(
      routeVersion: _routeVersion,
    );
    _state = CompanionNavigationState.navigationStopped;
    _bleService?.clearActiveNavPacket(reason: 'Navegación detenida');
    if (_bleService != null && _bleService.currentState.isReadyForNavigation) {
      await _bleService.stopNavigation();
    }
  }

  /// Refleja cambios en la conexión BLE del Tripper Pod sin disparar reconexiones en bucle (Regla 5).
  void onBleConnectionStateChanged(TripperConnectionState bleState) {
    if (bleState.isReadyForNavigation) {
      if (_activeExternalInstruction != null &&
          _activeExternalInstruction!.isCompatibleWithTripper) {
        _state = CompanionNavigationState.navigationActive;
      } else {
        _state = CompanionNavigationState.bleConnected;
      }
      return;
    }

    switch (bleState) {
      case TripperConnectionState.idle:
        _recomputeStateAfterSelection();
        break;
      case TripperConnectionState.scanning:
      case TripperConnectionState.deviceFound:
      case TripperConnectionState.connecting:
      case TripperConnectionState.gattConnected:
      case TripperConnectionState.servicesDiscovered:
      case TripperConnectionState.characteristicIdentified:
      case TripperConnectionState.authPending:
        _state = CompanionNavigationState.bleConnecting;
        break;
      case TripperConnectionState.authenticated:
      case TripperConnectionState.bidirectionalVerified:
      case TripperConnectionState.testMessageSent:
      case TripperConnectionState.connected:
        _state = CompanionNavigationState.bleConnected;
        break;
      case TripperConnectionState.disconnecting:
      case TripperConnectionState.disconnected:
      case TripperConnectionState.bluetoothDisabled:
      case TripperConnectionState.permissionDenied:
      case TripperConnectionState.permissionRequired:
      case TripperConnectionState.error:
        _state = CompanionNavigationState.bleDisconnected;
        break;
    }
  }

  void _recomputeStateAfterSelection() {
    if (_activeSource.capabilities.requiresNotificationAccess &&
        !_hasNotificationPermission) {
      _state = CompanionNavigationState.awaitingPermission;
    } else {
      _state = CompanionNavigationState.sourceSelected;
    }
    _curvatureInfo = _activeSource.evaluateCurvature(
      routeVersion: _routeVersion,
    );
  }
}
