import '../entities/tripper_connection_state.dart';
import '../entities/tripper_device.dart';
import '../entities/tripper_gatt_info.dart';
import '../entities/tripper_maneuver_payload.dart';

/// Contrato abstracto para el servicio de comunicación Bluetooth Low Energy
/// con el Royal Enfield Tripper Pod.
abstract class TripperBleService {
  /// Flujo continuo de cambios de estado de la conexión.
  Stream<TripperConnectionState> get stateStream;

  /// Estado actual síncrono.
  TripperConnectionState get currentState;

  /// Dispositivo actualmente conectado o en proceso de conexión.
  TripperDevice? get connectedDevice;

  /// Flujo de dispositivos descubiertos durante el escaneo.
  Stream<List<TripperDevice>> get discoveredDevicesStream;

  /// Lista actual de dispositivos descubiertos.
  List<TripperDevice> get discoveredDevices;

  /// Flujo de servicios y características GATT descubiertos en el dispositivo conectado.
  Stream<List<TripperGattService>> get discoveredGattServicesStream;

  /// Lista actual de servicios GATT descubiertos.
  List<TripperGattService> get discoveredGattServices;

  /// Flujo de líneas de registro de diagnóstico en tiempo real.
  Stream<String> get diagnosticLogStream;

  /// Historial en memoria de eventos de diagnóstico.
  List<String> get diagnosticLogs;

  /// Comprueba si el hardware Bluetooth está encendido y disponible.
  Future<bool> isBluetoothAvailable();

  /// Inicia el escaneo pasivo/activo de dispositivos BLE cercanos.
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)});

  /// Detiene el escaneo BLE activo.
  Future<void> stopScan();

  /// Solicita conectar con un dispositivo específico tras acción expresa del usuario.
  Future<bool> connect(TripperDevice device);

  /// Desconecta de forma segura el enlace activo.
  Future<void> disconnect();

  /// Envía experimentalmente una maniobra de navegación (solo tras conexión validada).
  Future<bool> sendManeuver(TripperManeuverPayload maneuver);

  /// Limpia el búfer de logs de diagnóstico.
  void clearDiagnosticLogs();
}
