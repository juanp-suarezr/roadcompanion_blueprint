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

  /// Envía una maniobra de navegación hacia el display del Tripper Pod.
  Future<bool> sendManeuver(TripperManeuverPayload maneuver);

  /// Envía una trama binaria de 20 bytes directamente a la característica NXP Wireless UART.
  Future<bool> sendRawPacket(List<int> bytes) async => false;

  /// Envía un mensaje de prueba controlado y validado para verificar la aceptación física del Pod.
  Future<bool> sendTestMessage() async => false;

  /// Envía el PIN de emparejamiento ingresado por el usuario (CMD 0x20).
  Future<bool> sendPin(String pin) async => false;

  /// Última trama transmitida en formato hexadecimal legible (ej. "10 11 15 00 FA 01 ...").
  String? get lastPacketSentHex => null;

  /// Resultado o confirmación de la última transmisión efectuada.
  String? get lastTransmissionResult => null;

  /// Momento exacto en que se estableció la conexión física GATT.
  DateTime? get connectedSince => null;

  /// Contador acumulado de desconexiones observadas durante la sesión.
  int get disconnectCount => 0;

  /// Etapa exacta donde ocurrió el último error de conexión o GATT.
  String? get lastErrorStage => null;

  /// Detalle técnico del último error presentado.
  String? get lastErrorDetail => null;

  /// Último error registrado durante el escaneo o procesamiento de dispositivos BLE.
  String? get lastScanError => null;

  /// Flujo opcional de errores de escaneo.
  Stream<String?> get scanErrorStream => const Stream.empty();

  /// Limpia el búfer de logs de diagnóstico.
  void clearDiagnosticLogs();

  /// Limpia la lista de dispositivos descubiertos en memoria.
  void clearDiscoveredDevices() {}

  /// Fase actual de la conexión BLE ('deteniendo_escaneo', 'solicitando_enlace', 'esperando_confirmacion', 'descubriendo_servicios', 'conectado', 'error', 'cancelado').
  String? get currentConnectionPhase => null;

  /// Indica si hay un proceso de conexión en curso actualmente.
  bool get isConnecting => false;

  /// Cancela la solicitud de conexión en curso de forma segura.
  Future<void> cancelPendingConnection() async {}

  /// Genera y exporta un informe técnico completo de diagnóstico BLE sin credenciales.
  String exportFullDiagnosticReport() => '';
}
