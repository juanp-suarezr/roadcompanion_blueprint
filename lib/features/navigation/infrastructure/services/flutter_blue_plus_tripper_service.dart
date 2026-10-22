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
  final _devicesController = StreamController<List<TripperDevice>>.broadcast();
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
  bool _isConnecting = false;
  bool _isCancelRequested = false;
  String? _currentConnectionPhase;

  @override
  bool get isConnecting => _isConnecting;

  @override
  String? get currentConnectionPhase => _currentConnectionPhase;

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
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
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

              final existingIndex = _discoveredDevices.indexWhere(
                (d) => d.id == evaluated.id,
              );
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
        },
        onError: (e) {
          final errMsg = 'Error en flujo de resultados de escaneo BLE: $e';
          _log('[ERROR] $errMsg');
          _lastScanError = errMsg;
          _errorController.add(errMsg);
        },
      );

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
  Future<void> cancelPendingConnection() async {
    if (!_isConnecting) return;
    _isCancelRequested = true;
    _currentConnectionPhase = 'cancelado';
    _log('Cancelación de conexión solicitada expresamente por el usuario.');
    try {
      await _activeBleDevice?.disconnect();
    } catch (_) {}
    _isConnecting = false;
    _setState(TripperConnectionState.idle);
  }

  @override
  Future<bool> connect(TripperDevice device) async {
    if (_isConnecting) {
      _log('Intento de conexión ignorado: ya existe una conexión en curso.');
      return false;
    }

    _isConnecting = true;
    _isCancelRequested = false;
    final stopwatch = Stopwatch()..start();

    final nowIso = DateTime.now().toIso8601String();
    _log('=== INTENTO DE CONEXIÓN BLE ===');
    _log(
      'Hora: $nowIso | Dispositivo: "${device.name}" | ID: ${device.id} | RSSI: ${device.rssi} dBm',
    );
    _log(
      'Candidato Tripper: ${device.isTripperCandidate} (Confianza: ${device.confidenceLevel})',
    );
    if (device.name.toUpperCase().contains('RE_DISP')) {
      _log(
        'NOTA: Dispositivo detectado coincide con el candidato RE_DISP. Identidad NO confirmada hasta verificar especificación GATT.',
      );
    }

    try {
      // 1. Detener el escaneo previo y esperar a que finalice en el stack nativo
      _currentConnectionPhase = 'deteniendo_escaneo';
      _log(
        'Fase 1/4: Deteniendo escaneo BLE previo para liberar el controlador...',
      );
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        try {
          await FlutterBluePlus.isScanning
              .where((s) => !s)
              .first
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (_isCancelRequested) {
        _log('Conexión cancelada antes de iniciar el enlace.');
        _currentConnectionPhase = 'cancelado';
        _isConnecting = false;
        _setState(TripperConnectionState.idle);
        return false;
      }

      // 2. Solicitud de enlace GATT
      _currentConnectionPhase = 'solicitando_enlace';
      _setState(TripperConnectionState.connecting);
      _log(
        'Fase 2/4: Solicitando enlace GATT con ${device.id} (Timeout 30s)...',
      );

      final bleDevice = BluetoothDevice.fromId(device.id);
      _activeBleDevice = bleDevice;

      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = bleDevice.connectionState.listen((state) {
        _log('Evento connectionState nativo: ${state.name}');
        if (state == BluetoothConnectionState.disconnected &&
            _currentState == TripperConnectionState.connected) {
          _setState(TripperConnectionState.idle);
          _connectedDevice = null;
          _activeBleDevice = null;
          _discoveredGattServices.clear();
          _gattServicesController.add(const []);
          _log(
            'Dispositivo desconectado de forma remota o por pérdida de señal.',
          );
        } else if (state == BluetoothConnectionState.connected &&
            _currentState != TripperConnectionState.connected &&
            _currentState != TripperConnectionState.connecting) {
          _log('Reconexión detectada. Rediscurriendo servicios GATT...');
          _discoverAndRecordServices(bleDevice, device);
        }
      });

      // 3. Conexión física con timeout de 30 segundos
      _currentConnectionPhase = 'esperando_confirmacion';
      _log('Fase 3/4: Esperando confirmación de conexión del periférico...');
      await bleDevice.connect(
        license: License.nonprofit,
        autoConnect: false,
        timeout: const Duration(seconds: 30),
      );

      if (_isCancelRequested) {
        _log('Conexión cancelada tras enlace.');
        await bleDevice.disconnect();
        _currentConnectionPhase = 'cancelado';
        _isConnecting = false;
        _setState(TripperConnectionState.idle);
        return false;
      }

      // 4. Descubrimiento de servicios y características GATT
      _currentConnectionPhase = 'descubriendo_servicios';
      _log(
        'Fase 4/4: Enlace confirmado. Descubriendo servicios y características GATT...',
      );
      final servicesCount = await _discoverAndRecordServices(bleDevice, device);

      _connectedDevice = device;
      _currentConnectionPhase = 'conectado';
      _setState(TripperConnectionState.connected);
      stopwatch.stop();

      _log('=============================================');
      _log('¡CONEXIÓN GATT EXITOSA!');
      _log('Dispositivo: "${device.name}" (${device.id})');
      _log('Servicios descubiertos: $servicesCount');
      _log(
        'Duración total: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)',
      );
      _log(
        'AVISO TÉCNICO: La identidad como Tripper Pod requiere verificar los UUIDs de servicios descubiertos. No se emitirán escrituras GATT.',
      );
      _log('=============================================');

      _isConnecting = false;
      return true;
    } catch (e) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final elapsedSec = (elapsedMs / 1000).toStringAsFixed(1);
      final failedPhase = _currentConnectionPhase ?? 'desconocida';

      _currentConnectionPhase = 'error';
      _setState(TripperConnectionState.error);
      _connectedDevice = null;
      _activeBleDevice = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);

      _log('=============================================');
      _log('[ERROR-CONEXION] Fallo en fase "$failedPhase"');
      _log('Dispositivo objetivo: "${device.name}" (${device.id})');
      _log('Duración hasta el fallo: $elapsedMs ms ($elapsedSec s)');
      _log('Excepción completa: $e');

      if (e is FlutterBluePlusException) {
        _log(
          'Detalles nativos: Código: ${e.code} | Descripción: ${e.description}',
        );
      }

      if (Platform.isAndroid || !kIsWeb) {
        _log('DIAGNÓSTICO SAMSUNG GALAXY / ANDROID 16:');
        _log(
          '1. Si el Tripper Pod requiere emparejamiento por PIN/clave, revisa la bandeja de notificaciones de Android por si apareció una alerta de "Solicitud de vinculación Bluetooth".',
        );
        _log(
          '2. Si el Tripper Pod estuvo encendido más de 120 segundos sin vincularse, apaga y enciende la llave de la moto para reiniciar la ventana de emparejamiento.',
        );
        _log(
          '3. Error 133 / GATT_ERROR suele ocurrir si el periférico rechazó la negociación de MTU o timeout de enlace.',
        );
      }
      _log('=============================================');

      _isConnecting = false;
      return false;
    }
  }

  Future<int> _discoverAndRecordServices(
    BluetoothDevice bleDevice,
    TripperDevice device,
  ) async {
    final services = await bleDevice.discoverServices();
    _log('Servicios GATT descubiertos: ${services.length}');

    _discoveredGattServices.clear();
    for (final service in services) {
      _log('-> Servicio UUID: ${service.uuid}');
      final charList = <TripperGattCharacteristic>[];
      for (final char in service.characteristics) {
        _log(
          '   -> Característica UUID: ${char.uuid} [Lectura: ${char.properties.read}, Escritura: ${char.properties.write}, Notificación: ${char.properties.notify}]',
        );
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
    return services.length;
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
      _currentConnectionPhase = null;
      _setState(TripperConnectionState.idle);
      _log('Desconexión completada.');
    } catch (e) {
      _log('Aviso al desconectar: $e');
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _currentConnectionPhase = null;
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

  @override
  String exportFullDiagnosticReport() {
    final buffer = StringBuffer();
    final now = DateTime.now().toIso8601String();
    buffer.writeln('=== INFORME DE DIAGNÓSTICO BLE — RESTELAR ===');
    buffer.writeln('Fecha/Hora: $now');
    buffer.writeln('Plataforma: ${kIsWeb ? "Web" : Platform.operatingSystem}');
    buffer.writeln('Estado de conexión: ${_currentState.name}');
    buffer.writeln('Fase de conexión: ${_currentConnectionPhase ?? "ninguna"}');
    buffer.writeln(
      'Dispositivo conectado: ${_connectedDevice != null ? "${_connectedDevice!.name} (${_connectedDevice!.id})" : "Ninguno"}',
    );
    buffer.writeln('Dispositivos descubiertos (${_discoveredDevices.length}):');
    for (final d in _discoveredDevices) {
      buffer.writeln(
        ' - "${d.name}" | ID: ${d.id} | RSSI: ${d.rssi} dBm | Candidato: ${d.isTripperCandidate} (${d.confidenceLevel})',
      );
    }
    buffer.writeln(
      'Servicios GATT descubiertos (${_discoveredGattServices.length}):',
    );
    for (final s in _discoveredGattServices) {
      buffer.writeln(' [Servicio] ${s.uuid}');
      for (final c in s.characteristics) {
        buffer.writeln(
          '   [Caract] ${c.uuid} (R:${c.canRead}, W:${c.canWrite}, N:${c.canNotify})',
        );
      }
    }
    buffer.writeln('--- REGISTRO COMPLETO DE EVENTOS (LOGS) ---');
    for (final log in _diagnosticLogs) {
      buffer.writeln(log);
    }
    buffer.writeln('=== FIN DEL INFORME ===');
    return buffer.toString();
  }
}
