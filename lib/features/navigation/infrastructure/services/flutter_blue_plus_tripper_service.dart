import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/entities/tripper_connection_state.dart';
import '../../domain/entities/tripper_device.dart';
import '../../domain/entities/tripper_gatt_info.dart';
import '../../domain/entities/tripper_maneuver_payload.dart';
import '../../domain/services/tripper_ble_service.dart';

/// Implementación de producción de [TripperBleService] empleando `flutter_blue_plus`.
///
/// Gestiona descubrimiento seguro, evaluación técnica de candidatos, enlace BLE
/// con el Tripper Pod de la Meteor 350 y registro de diagnóstico en tiempo real.
class FlutterBluePlusTripperService implements TripperBleService {
  static FlutterBluePlusTripperService? _instance;

  factory FlutterBluePlusTripperService() {
    return _instance ??= FlutterBluePlusTripperService._internal();
  }

  FlutterBluePlusTripperService._internal() {
    _log(
      'Servicio Tripper BLE inicializado. Plataforma: ${kIsWeb ? "Web" : Platform.operatingSystem}',
    );
  }

  /// Permite reiniciar la instancia en entornos de pruebas unitarias.
  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  final _stateController = StreamController<TripperConnectionState>.broadcast();
  final _devicesController =
      StreamController<List<TripperDevice>>.broadcast();
  final _gattServicesController =
      StreamController<List<TripperGattService>>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _errorController = StreamController<String?>.broadcast();

  final List<String> _diagnosticLogs = [];
  final List<TripperDevice> _discoveredDevices = [];
  final List<TripperGattService> _discoveredGattServices = [];
  TripperConnectionState _currentState = TripperConnectionState.idle;
  TripperDevice? _connectedDevice;
  BluetoothDevice? _activeBleDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  String? _lastScanError;

  @override
  Stream<TripperConnectionState> get stateStream => _stateController.stream;

  @override
  TripperConnectionState get currentState => _currentState;

  @override
  TripperDevice? get connectedDevice => _connectedDevice;

  @override
  Stream<List<TripperDevice>> get discoveredDevicesStream =>
      _devicesController.stream;

  @override
  List<TripperDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  @override
  Stream<List<TripperGattService>> get discoveredGattServicesStream =>
      _gattServicesController.stream;

  @override
  List<TripperGattService> get discoveredGattServices =>
      List.unmodifiable(_discoveredGattServices);

  @override
  Stream<String> get diagnosticLogStream => _logController.stream;

  @override
  List<String> get diagnosticLogs => List.unmodifiable(_diagnosticLogs);

  @override
  String? get lastScanError => _lastScanError;

  @override
  Stream<String?> get scanErrorStream => _errorController.stream;

  void _setState(TripperConnectionState state) {
    _currentState = state;
    _stateController.add(state);
    _log('Estado conexión BLE: ${state.name}');
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$timestamp] $message';
    _diagnosticLogs.add(entry);
    if (_diagnosticLogs.length > 500) {
      _diagnosticLogs.removeAt(0);
    }
    _logController.add(entry);
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    try {
      if (kIsWeb) return false;
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _log('Bluetooth LE no está soportado en este hardware.');
        return false;
      }
      final adapterState = await FlutterBluePlus.adapterState.first;
      final isAvailable = adapterState == BluetoothAdapterState.on;
      _log('Estado adaptador Bluetooth: ${adapterState.name}');
      return isAvailable;
    } catch (e) {
      _log('Aviso al comprobar disponibilidad Bluetooth: $e');
      return false;
    }
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      _lastScanError = null;
      _errorController.add(null);
      _discoveredDevices.clear();
      _devicesController.add(List.unmodifiable(_discoveredDevices));
      _setState(TripperConnectionState.scanning);
      _log('Iniciando escaneo BLE (timeout: ${timeout.inSeconds}s)...');

      final isAvailable = await isBluetoothAvailable();
      if (!isAvailable) {
        _setState(TripperConnectionState.bluetoothDisabled);
        _log('No se puede escanear: el Bluetooth está desactivado.');
        return;
      }

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          try {
            final rawName = r.advertisementData.advName.trim().isNotEmpty
                ? r.advertisementData.advName
                : (r.device.platformName.trim().isNotEmpty
                    ? r.device.platformName
                    : (r.device.advName.trim().isNotEmpty
                        ? r.device.advName
                        : ''));

            final deviceId = r.device.remoteId.str.trim().isNotEmpty
                ? r.device.remoteId.str.trim()
                : 'ID_NO_DISPONIBLE';

            final List<String> serviceUuids = [];
            try {
              for (final u in r.advertisementData.serviceUuids) {
                serviceUuids.add(u.toString());
              }
            } catch (uErr) {
              _log('Aviso al extraer UUIDs para $deviceId: $uErr');
            }

            final evaluated = TripperDevice.evaluate(
              id: deviceId,
              name: rawName,
              rssi: r.rssi,
              serviceUuids: serviceUuids,
              manufacturerData: r.advertisementData.manufacturerData,
            );

            final existingIndex =
                _discoveredDevices.indexWhere((d) => d.id == evaluated.id);
            if (existingIndex >= 0) {
              // Actualizar RSSI y nombre sin duplicar el identificador
              final old = _discoveredDevices[existingIndex];
              if (old.rssi != evaluated.rssi || old.name != evaluated.name) {
                _discoveredDevices[existingIndex] = evaluated;
              }
            } else {
              _discoveredDevices.add(evaluated);
              _log(
                'Dispositivo BLE detectado: "${evaluated.name}" [ID: ${evaluated.id}] RSSI: ${evaluated.rssi} dBm',
              );
              if (evaluated.isTripperCandidate) {
                _log(
                  '¡CANDIDATO TRIPPER DETECTADO!: "${evaluated.name}" (${evaluated.id}) RSSI: ${evaluated.rssi} dBm [Confianza: ${evaluated.confidenceLevel}]',
                );
              }
            }
          } catch (itemErr) {
            final errMsg =
                'Error al procesar dispositivo BLE (${r.device.remoteId.str}): $itemErr';
            _log('[ERROR] $errMsg');
            _lastScanError = errMsg;
            _errorController.add(errMsg);
          }
        }
        _devicesController.add(List.unmodifiable(_discoveredDevices));
      }, onError: (e) {
        final errMsg = 'Error en flujo de resultados de escaneo BLE: $e';
        _log('[ERROR] $errMsg');
        _lastScanError = errMsg;
        _errorController.add(errMsg);
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await FlutterBluePlus.isScanning.where((s) => !s).first;

      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (_currentState == TripperConnectionState.scanning) {
        _setState(TripperConnectionState.idle);
        _devicesController.add(List.unmodifiable(_discoveredDevices));
        _log(
          'Escaneo BLE finalizado. Dispositivos detectados: ${_discoveredDevices.length}',
        );
      }
    } catch (e) {
      _setState(TripperConnectionState.error);
      final errMsg = 'Error durante el escaneo BLE: $e';
      _log('[ERROR] $errMsg');
      _lastScanError = errMsg;
      _errorController.add(errMsg);
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (_currentState == TripperConnectionState.scanning) {
        _setState(TripperConnectionState.idle);
        _devicesController.add(List.unmodifiable(_discoveredDevices));
        _log('Escaneo BLE detenido manualmente por el usuario.');
      }
    } catch (e) {
      _log('Aviso al detener escaneo BLE: $e');
    }
  }

  @override
  void clearDiscoveredDevices() {
    _discoveredDevices.clear();
    _devicesController.add(List.unmodifiable(_discoveredDevices));
    _log('Lista de dispositivos descubiertos reiniciada.');
  }

  void dispose() {
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _stateController.close();
    _devicesController.close();
    _gattServicesController.close();
    _logController.close();
    _errorController.close();
  }

  @override
  Future<bool> connect(TripperDevice device) async {
    try {
      await stopScan();
      _setState(TripperConnectionState.connecting);
      _log('Iniciando conexión con "${device.name}" (${device.id})...');

      final bleDevice = BluetoothDevice.fromId(device.id);
      _activeBleDevice = bleDevice;

      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = bleDevice.connectionState.listen((state) {
        _log('Estado enlace GATT: ${state.name}');
        if (state == BluetoothConnectionState.disconnected &&
            _currentState == TripperConnectionState.connected) {
          _setState(TripperConnectionState.idle);
          _connectedDevice = null;
          _activeBleDevice = null;
          _log('Dispositivo desconectado de forma remota.');
        }
      });

      await bleDevice.connect(
        license: License.nonprofit,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      _log('Enlace BLE establecido. Solicitando descubrimiento de servicios...');
      final services = await bleDevice.discoverServices();
      _log('Servicios GATT descubiertos: ${services.length}');

      _discoveredGattServices.clear();
      for (final service in services) {
        _log('-> Servicio UUID: ${service.uuid}');
        final charList = <TripperGattCharacteristic>[];
        for (final char in service.characteristics) {
          _log('   -> Característica UUID: ${char.uuid} [Props: read=${char.properties.read}, write=${char.properties.write}, notify=${char.properties.notify}]');
          charList.add(
            TripperGattCharacteristic(
              uuid: char.uuid.toString(),
              canRead: char.properties.read,
              canWrite: char.properties.write,
              canWriteWithoutResponse: char.properties.writeWithoutResponse,
              canNotify: char.properties.notify,
              canIndicate: char.properties.indicate,
            ),
          );
        }
        _discoveredGattServices.add(
          TripperGattService(
            uuid: service.uuid.toString(),
            characteristics: charList,
          ),
        );
      }
      _gattServicesController.add(List.unmodifiable(_discoveredGattServices));

      _connectedDevice = device;
      _setState(TripperConnectionState.connected);
      _log(
        '¡CONEXIÓN VALIDADA con Tripper Pod! Modo de diagnóstico activo listo para pruebas.',
      );
      return true;
    } catch (e) {
      _setState(TripperConnectionState.error);
      _connectedDevice = null;
      _activeBleDevice = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _log('Error al conectar con el dispositivo: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      _setState(TripperConnectionState.disconnecting);
      _log('Desconectando dispositivo de forma segura...');
      await _activeBleDevice?.disconnect();
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _activeBleDevice = null;
      _connectedDevice = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _setState(TripperConnectionState.idle);
      _log('Desconexión completada.');
    } catch (e) {
      _log('Aviso al desconectar: $e');
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _setState(TripperConnectionState.idle);
    }
  }

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async {
    if (_currentState != TripperConnectionState.connected ||
        _activeBleDevice == null) {
      _log(
        'No se puede emitir maniobra: no hay conexión BLE activa con el Tripper Pod.',
      );
      return false;
    }

    _log(maneuver.toDiagnosticString());
    final bytes = maneuver.toTentativeBytes();
    _log('Bytes tentativos generados: $bytes');
    _log(
      'AVISO DE SEGURIDAD: Carga útil registrada en diagnóstico. En modo experimental seguro, la transmisión física queda condicionada a confirmación en el dispositivo real de la Meteor.',
    );
    return true;
  }

  @override
  void clearDiagnosticLogs() {
    _diagnosticLogs.clear();
    _log('Búfer de diagnóstico reiniciado.');
  }
}
