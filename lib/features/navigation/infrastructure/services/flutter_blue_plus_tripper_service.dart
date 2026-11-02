import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/tripper_connection_state.dart';
import '../../domain/entities/tripper_device.dart';
import '../../domain/entities/tripper_gatt_info.dart';
import '../../domain/entities/tripper_maneuver_payload.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../domain/services/tripper_protocol.dart';

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
  BluetoothCharacteristic? _writeCharacteristic;
  Timer? _keepAliveTimer;
  Timer? _probeRetentionTimer;
  int _probeRetentionSeconds = 0;
  DateTime? _lastPacketSentTime;
  DateTime? _lastPacketReceivedTime;
  DateTime? _lastNavPacketSentTime;
  String? _lastNavPacketSentHex;
  DateTime? _lastKeepAliveSentTime;
  bool _isLocalDisconnectRequested = false;
  DateTime? _connectedSince;
  int _disconnectCount = 0;
  String? _lastPacketSentHex;
  String? _lastTransmissionResult;
  String? _lastErrorStage;
  String? _lastErrorDetail;

  final List<_QueuedPacket> _packetQueue = [];
  bool _isProcessingQueue = false;
  Uint8List? _activeNavPacket;
  String? _activeNavDescription;
  bool _isNavScreenActive = false;
  bool _isTestManeuverActive = false;

  @override
  bool get isNavScreenActive => _isNavScreenActive;

  @override
  bool get isTestManeuverActive => _isTestManeuverActive;

  static const MethodChannel _controlChannel = MethodChannel(
    'es.estela/bridge_controls',
  );
  static const EventChannel _gattServerEventChannel = EventChannel(
    'es.estela/tripper_gatt_server_events',
  );
  StreamSubscription? _gattServerSubscription;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  String? _lastScanError;
  bool _isConnecting = false;
  bool _isCancelRequested = false;
  String? _currentConnectionPhase;

  Future<void> _ensureLocalGattServerStarted() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final res = await _controlChannel.invokeMethod<Map>(
        'startTripperGattServer',
      );
      final msg = res?['message'] ?? 'OK';
      final ok = res?['success'] ?? false;
      _log('[GATT-SERVER-LOCAL] ${ok ? "Iniciado" : "Aviso"}: $msg');

      _gattServerSubscription ??= _gattServerEventChannel
          .receiveBroadcastStream()
          .listen(
            (dynamic event) {
              if (event is Map) {
                final type = event['type'];
                if (type == 'data') {
                  final hex = event['hex'];
                  final addr = event['address'];
                  _lastPacketReceivedTime = DateTime.now();
                  _log('[RX-GATT-SERVER] ($addr): $hex');
                } else if (type == 'connection') {
                  final state = event['state'];
                  final addr = event['address'];
                  _log('[GATT-SERVER-LOCAL] Periférico ($addr) estado: $state');
                }
              }
            },
            onError: (err) {
              _log('[GATT-SERVER-LOCAL] Error en stream de eventos: $err');
            },
          );
    } catch (e) {
      _log('[GATT-SERVER-LOCAL] No se pudo inicializar: $e');
    }
  }

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

  @override
  String? get lastPacketSentHex => _lastPacketSentHex;

  @override
  DateTime? get lastNavPacketSentTime => _lastNavPacketSentTime;

  @override
  String? get lastNavPacketSentHex => _lastNavPacketSentHex;

  @override
  DateTime? get lastKeepAliveSentTime => _lastKeepAliveSentTime;

  @override
  bool get isLocalDisconnectRequested => _isLocalDisconnectRequested;

  @override
  String? get lastTransmissionResult => _lastTransmissionResult;

  @override
  DateTime? get connectedSince => _connectedSince;

  @override
  int get disconnectCount => _disconnectCount;

  @override
  String? get lastErrorStage => _lastErrorStage;

  @override
  String? get lastErrorDetail => _lastErrorDetail;

  void _setState(TripperConnectionState state) {
    _currentState = state;
    _stateController.add(state);
    _log('Estado conexión BLE: ${state.displayName} (${state.name})');
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
      _log(
        '[SCAN-INICIO] Preparando búsqueda BLE (duración máxima: ${timeout.inSeconds}s)...',
      );

      final isAvailable = await isBluetoothAvailable();
      if (!isAvailable) {
        _setState(TripperConnectionState.bluetoothDisabled);
        _log(
          '[SCAN-ERROR] No se puede escanear: el Bluetooth está desactivado.',
        );
        return;
      }

      // Detener cualquier escaneo residual previo en el adaptador Android
      if (!kIsWeb && FlutterBluePlus.isScanningNow) {
        _log(
          '[SCAN-RESET] Deteniendo escaneo previo activo en el adaptador Bluetooth...',
        );
        try {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (stopErr) {
          _log(
            '[SCAN-RESET] Aviso al reiniciar adaptador de escaneo: $stopErr',
          );
        }
      }

      // Auditoría de permisos en Android 12+ (BLUETOOTH_SCAN, BLUETOOTH_CONNECT)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final scanPerm = await Permission.bluetoothScan.status;
          final connectPerm = await Permission.bluetoothConnect.status;
          _log(
            '[SCAN-PERMISOS] Estado permisos Android: Scan=${scanPerm.name}, Connect=${connectPerm.name}',
          );
        } catch (permErr) {
          _log('[SCAN-PERMISOS] Info consulta permisos: $permErr');
        }
      }

      // Consulta preventiva de dispositivos vinculados en el sistema (por si RE_DISP ya está emparejado en el OS)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final bonded = await FlutterBluePlus.bondedDevices;
          if (bonded.isNotEmpty) {
            _log(
              '[SCAN-VINCULADOS] Consultando ${bonded.length} periférico(s) vinculado(s) en Android...',
            );
            for (final b in bonded) {
              final rawName = b.platformName.trim().isNotEmpty
                  ? b.platformName
                  : (b.advName.trim().isNotEmpty ? b.advName : '');
              final devId = b.remoteId.str.trim();
              if (devId.isNotEmpty) {
                final evaluated = TripperDevice.evaluate(
                  id: devId,
                  name: rawName,
                  rssi: -50,
                );
                final idx = _discoveredDevices.indexWhere(
                  (d) => d.id == evaluated.id,
                );
                if (idx < 0) {
                  _discoveredDevices.add(evaluated);
                  _log(
                    '[SCAN-VINCULADO] Dispositivo vinculado registrado: "${evaluated.name}" [ID: ${evaluated.id}] (Candidato: ${evaluated.isTripperCandidate})',
                  );
                }
              }
            }
            _devicesController.add(List.unmodifiable(_discoveredDevices));
          }
        } catch (bErr) {
          _log('[SCAN-VINCULADOS] Info consulta vinculados: $bErr');
        }
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
                _log(
                  '[SCAN-UUID-AVISO] Error al extraer UUIDs para $deviceId: $uErr',
                );
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
                final shouldUpdate =
                    old.rssi != evaluated.rssi ||
                    old.name != evaluated.name ||
                    (!old.isTripperCandidate && evaluated.isTripperCandidate);
                if (shouldUpdate) {
                  _discoveredDevices[existingIndex] = evaluated;
                  if (!old.isTripperCandidate && evaluated.isTripperCandidate) {
                    _log(
                      '[SCAN-CANDIDATO] ¡CANDIDATO TRIPPER IDENTIFICADO!: "${evaluated.name}" (${evaluated.id}) RSSI: ${evaluated.rssi} dBm [Confianza: ${evaluated.confidenceLevel}]',
                    );
                  }
                }
              } else {
                _discoveredDevices.add(evaluated);
                _log(
                  '[SCAN-RESULTADO] Dispositivo detectado: "${evaluated.name}" [ID: ${evaluated.id}] RSSI: ${evaluated.rssi} dBm',
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
              _log('[SCAN-ITEM-ERROR] $errMsg');
              _lastScanError = errMsg;
              _errorController.add(errMsg);
            }
          }
          _devicesController.add(List.unmodifiable(_discoveredDevices));
        },
        onError: (e) {
          final errMsg = 'Error en flujo de resultados de escaneo BLE: $e';
          _log('[SCAN-STREAM-ERROR] $errMsg');
          _lastScanError = errMsg;
          _errorController.add(errMsg);
        },
      );

      // androidLegacy: true fuerza al radio BLE a escanear paquetes publicitarios estándar 1M PHY (Bluetooth 4.2 LE),
      // lo cual es indispensable para el Royal Enfield Tripper Pod y evita anomalías en controladores BLE Samsung/Android 14.
      _log(
        '[SCAN-RADIO] Iniciando escáner BLE en modo legacy 1M PHY (timeout: ${timeout.inSeconds}s)...',
      );
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidLegacy: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      try {
        await FlutterBluePlus.isScanning
            .where((s) => !s)
            .first
            .timeout(timeout + const Duration(seconds: 2));
      } catch (_) {
        _log('[SCAN-TIMEOUT] Límite de tiempo agotado. Deteniendo escáner...');
        await FlutterBluePlus.stopScan();
      }

      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (_currentState == TripperConnectionState.scanning) {
        _setState(TripperConnectionState.idle);
        _devicesController.add(List.unmodifiable(_discoveredDevices));
        _log(
          '[SCAN-FINALIZADO] Escaneo BLE completado. Dispositivos totales detectados: ${_discoveredDevices.length}',
        );
      }
    } catch (e) {
      _setState(TripperConnectionState.error);
      final errMsg = 'Error durante el escaneo BLE: $e';
      _log('[SCAN-ERROR] $errMsg');
      _lastScanError = errMsg;
      _errorController.add(errMsg);
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      _log('[SCAN-CANCEL] Cancelando escaneo BLE a solicitud del usuario...');
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (_currentState == TripperConnectionState.scanning) {
        _setState(TripperConnectionState.idle);
        _devicesController.add(List.unmodifiable(_discoveredDevices));
        _log(
          '[SCAN-CANCEL] Escaneo BLE detenido manualmente. Dispositivos detectados: ${_discoveredDevices.length}',
        );
      }
    } catch (e) {
      _log('[SCAN-ERROR] Aviso al detener escaneo BLE: $e');
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
  Future<bool> probeGattOnly(TripperDevice device) async {
    return _connectInternal(device, probeOnly: true);
  }

  @override
  Future<bool> connect(TripperDevice device) async {
    return _connectInternal(device, probeOnly: false);
  }

  Future<bool> _connectInternal(
    TripperDevice device, {
    required bool probeOnly,
  }) async {
    if (_isConnecting) {
      _log('Intento de conexión ignorado: ya existe una conexión en curso.');
      return false;
    }

    _isConnecting = true;
    _isCancelRequested = false;
    final stopwatch = Stopwatch()..start();

    final nowIso = DateTime.now().toIso8601String();
    _log(
      '=== INTENTO DE CONEXIÓN BLE ${probeOnly ? "(MODO SONDA GATT AISLADA)" : "(PROTOCOLO COMPLETO)"} ===',
    );
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
      // 0. Inicializar servidor GATT local en Android (para recibir respuestas del Pod según protocolo documentado)
      await _ensureLocalGattServerStarted();

      // 1. Detener el escaneo previo y esperar estabilización del stack nativo
      _currentConnectionPhase = 'deteniendo_escaneo';
      _log(
        'Fase 1/6: Deteniendo escaneo BLE previo para liberar el controlador Bluetooth...',
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

      // Holgura imprescindible para Samsung Galaxy / Android 16 antes de iniciar conexión directa
      await Future.delayed(const Duration(milliseconds: 350));

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
        'Fase 2/6: Solicitando enlace GATT con ${device.id} (autoConnect: false, Timeout 30s)...',
      );

      final bleDevice = BluetoothDevice.fromId(device.id);
      _activeBleDevice = bleDevice;

      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = bleDevice.connectionState.listen((state) {
        final now = DateTime.now();
        final msSinceLastTx = _lastPacketSentTime != null
            ? now.difference(_lastPacketSentTime!).inMilliseconds
            : -1;
        final msSinceLastRx = _lastPacketReceivedTime != null
            ? now.difference(_lastPacketReceivedTime!).inMilliseconds
            : -1;
        final msSinceLastNav = _lastNavPacketSentTime != null
            ? now.difference(_lastNavPacketSentTime!).inMilliseconds
            : -1;
        final msSinceLastKeepAlive = _lastKeepAliveSentTime != null
            ? now.difference(_lastKeepAliveSentTime!).inMilliseconds
            : -1;

        _log(
          '[REstelar:BLE] [GATT_CONNECTION_STATE] Evento connectionState nativo: ${state.name}',
        );
        if (state == BluetoothConnectionState.disconnected &&
            (_currentState.isReadyForNavigation ||
                _currentState == TripperConnectionState.gattConnected ||
                _currentState == TripperConnectionState.servicesDiscovered ||
                _currentState == TripperConnectionState.disconnecting)) {
          final wasLocal = _isLocalDisconnectRequested;
          _disconnectCount++;
          _probeRetentionTimer?.cancel();
          _probeRetentionTimer = null;
          _keepAliveTimer?.cancel();
          _keepAliveTimer = null;
          _writeCharacteristic = null;
          _connectedDevice = null;
          _activeBleDevice = null;
          _activeNavPacket = null;
          _activeNavDescription = null;
          _isNavScreenActive = false;
          _isTestManeuverActive = false;
          _clearQueue(reason: 'Desconexión de enlace BLE');
          _discoveredGattServices.clear();
          _gattServicesController.add(const []);
          _currentConnectionPhase = 'desconectado';
          _setState(TripperConnectionState.disconnected);

          if (wasLocal) {
            _log(
              '[BLE-DISCONNECT-EVENT: LOCAL_REQUESTED] Desconexión completada tras solicitud local. '
              'Desconexión acumulada #$_disconnectCount | '
              'Tiempo desde último TX: ${msSinceLastTx >= 0 ? "${msSinceLastTx}ms" : "N/A"} | '
              'Tiempo desde último RX: ${msSinceLastRx >= 0 ? "${msSinceLastRx}ms" : "N/A"}',
            );
          } else {
            _log(
              '[BLE-DISCONNECT-EVENT: REMOTE_PEER_OR_WATCHDOG] El enlace BLE fue terminado por el periférico remoto (Tripper Pod) o su watchdog de hardware. '
              'Desconexión acumulada #$_disconnectCount | '
              'Tiempo desde último TX: ${msSinceLastTx >= 0 ? "${msSinceLastTx}ms" : "N/A"} | '
              'Tiempo desde último RX: ${msSinceLastRx >= 0 ? "${msSinceLastRx}ms" : "N/A"} | '
              'Tiempo desde última trama navegación (0x10 0x11): ${msSinceLastNav >= 0 ? "${msSinceLastNav}ms" : "N/A"} | '
              'Tiempo desde último keepalive (PING_FW): ${msSinceLastKeepAlive >= 0 ? "${msSinceLastKeepAlive}ms" : "N/A"} | '
              'Última trama enviada: ${_lastPacketSentHex ?? "ninguna"} | '
              'DIAGNÓSTICO: Si la desconexión ocurrió ~5s después de detener la navegación, corresponde al watchdog de pantalla nativo del firmware del Tripper Pod al cesar el envío de tramas 0x10 0x11.',
            );
          }
          _isLocalDisconnectRequested = false;
        }
      });

      // 3. Conexión física con timeout de 30 segundos
      // IMPORTANTE: mtu: null es OBLIGATORIO para el Tripper Pod.
      // Por defecto FlutterBluePlus solicita MTU 512 en Android. El microcontrolador NXP
      // del Tripper Pod opera en MTU estándar de 23 bytes (20 bytes de carga útil) y
      // desconecta la sesión si el cliente intenta negociar MTU expandido (código 147 / requestMtu error).
      _currentConnectionPhase = 'esperando_confirmacion_gatt';
      _log(
        'Fase 3/6: Solicitando enlace GATT con MTU estándar fijo (sin negociación 512)...',
      );
      await bleDevice.connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: null,
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

      _connectedSince = DateTime.now();
      _setState(TripperConnectionState.gattConnected);
      _log('¡Enlace GATT establecido físicamente!');

      // Pausa preventiva para permitir que Android 16 (Samsung Galaxy A35) estabilice el socket GATT
      await Future.delayed(const Duration(milliseconds: 350));

      // 4. Descubrimiento de servicios y características GATT
      // IMPORTANTE: subscribeToServicesChanged: false evita la excepción PlatformException(setNotifyValue)
      _currentConnectionPhase = 'descubriendo_servicios';
      _log(
        'Fase 4/6: Enlace GATT confirmado. Descubriendo servicios y características (subscribeToServicesChanged: false)...',
      );
      final services = await _discoverAndRecordServices(bleDevice, device);
      _setState(TripperConnectionState.servicesDiscovered);

      if (probeOnly) {
        _connectedDevice = device;
        _currentConnectionPhase = 'sonda_completada';
        stopwatch.stop();

        _log('=============================================');
        _log('¡SONDA GATT AISLADA EXITOSA (SIN TRÁFICO)!');
        _log('Dispositivo: "${device.name}" (${device.id})');
        _log('Servicios descubiertos: ${services.length}');
        _log(
          'Duración hasta enlace y descubrimiento: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)',
        );
        _log(
          'Manteniendo conexión abierta para monitorizar estabilidad de retención...',
        );
        _log('=============================================');

        _probeRetentionSeconds = 0;
        _probeRetentionTimer?.cancel();
        _probeRetentionTimer = Timer.periodic(const Duration(seconds: 1), (
          timer,
        ) {
          _probeRetentionSeconds++;
          if (_probeRetentionSeconds % 5 == 0 || _probeRetentionSeconds <= 5) {
            _log(
              '[SONDA-GATT] Enlace retenido de forma estable: ${_probeRetentionSeconds}s',
            );
          }
        });

        _isConnecting = false;
        return true;
      }

      // 5. Identificación de la característica de comunicación NXP Wireless UART
      _currentConnectionPhase = 'identificando_caracteristica';
      _log(
        'Fase 5/6: Localizando característica NXP Wireless UART (UUID 01FF0101)...',
      );

      BluetoothCharacteristic? targetChar;
      for (final s in services) {
        final sUuid = s.uuid.toString().toLowerCase();
        if (sUuid.contains('01ff0100') || sUuid.contains('fee7')) {
          for (final c in s.characteristics) {
            final cUuid = c.uuid.toString().toLowerCase();
            if (cUuid.contains('01ff0101') ||
                cUuid.contains('fec7') ||
                c.properties.write ||
                c.properties.writeWithoutResponse) {
              targetChar = c;
              break;
            }
          }
        }
      }

      // Fallback si el UUID no tuvo coincidencia exacta
      if (targetChar == null) {
        for (final s in services) {
          for (final c in s.characteristics) {
            if (c.properties.write || c.properties.writeWithoutResponse) {
              targetChar = c;
              _log(
                'Aviso técnico: UUID exacto NXP no encontrado en publicidad. Empleando característica con soporte de escritura: ${c.uuid}',
              );
              break;
            }
          }
          if (targetChar != null) break;
        }
      }

      if (targetChar == null) {
        throw Exception(
          'No se localizó ninguna característica GATT con permiso de escritura en el periférico.',
        );
      }

      _writeCharacteristic = targetChar;
      _setState(TripperConnectionState.characteristicIdentified);
      _log(
        'Característica de comunicación identificada: ${targetChar.uuid} (Write: ${targetChar.properties.write}, WriteNoResp: ${targetChar.properties.writeWithoutResponse})',
      );

      // 6. Autenticación y Handshake (esperar ~200 ms entre descubrimiento y primera escritura según PROTOCOL.md)
      _currentConnectionPhase = 'autenticacion';
      _setState(TripperConnectionState.authPending);
      _log(
        'Fase 6/6: Esperando 200 ms de estabilización antes del handshake de protocolo...',
      );
      await Future.delayed(const Duration(milliseconds: 200));

      if (_isCancelRequested) {
        _log('Conexión cancelada antes del handshake.');
        await bleDevice.disconnect();
        _currentConnectionPhase = 'cancelado';
        _isConnecting = false;
        _setState(TripperConnectionState.idle);
        return false;
      }

      // Transmitir HANDSHAKE_RESUME (0x21 00 ... 40 45)
      _log('Transmitiendo paquete HANDSHAKE_RESUME (20 bytes)...');
      final handshakeOk = await _enqueuePacket(
        TripperProtocol.packetHandshakeResume,
        description: 'HANDSHAKE_RESUME',
      );

      if (!handshakeOk) {
        _log('Aviso: Fallo al transmitir handshake inicial.');
      } else {
        _setState(TripperConnectionState.authenticated);
        _log('¡Sesión autenticada mediante protocolo Tripper Pod!');
      }

      // Esperar 150 ms antes de enviar la sincronización de hora
      await Future.delayed(const Duration(milliseconds: 150));
      final timePacket = TripperProtocol.buildSetTimeNowPacket();
      await _enqueuePacket(
        timePacket,
        description: 'CMD_SET_TIME (sincronización de reloj)',
      );

      // Iniciar el temporizador de watchdog Keepalive (PING_FW cada 2s o refresh si hay pantalla)
      _startKeepAliveTimer();

      _connectedDevice = device;
      _currentConnectionPhase = 'conectado';
      _setState(TripperConnectionState.connected);
      stopwatch.stop();

      _log('=============================================');
      _log('¡CONEXIÓN Y SESIÓN TRIPPER POD EXITOSA!');
      _log('Dispositivo: "${device.name}" (${device.id})');
      _log('Servicios descubiertos: ${services.length}');
      _log('Característica de escritura activa: ${targetChar.uuid}');
      _log(
        'Duración total: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)',
      );
      _log('Watchdog de keepalive activo: PING_FW cada 2000 ms.');
      _log('=============================================');

      _isConnecting = false;
      return true;
    } catch (e) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final elapsedSec = (elapsedMs / 1000).toStringAsFixed(1);
      final failedPhase = _currentConnectionPhase ?? 'desconocida';

      _lastErrorStage = failedPhase;
      _lastErrorDetail = e.toString();
      _probeRetentionTimer?.cancel();
      _probeRetentionTimer = null;
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      _writeCharacteristic = null;
      _currentConnectionPhase = 'error';
      _setState(TripperConnectionState.error);
      _connectedDevice = null;
      _activeBleDevice = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);

      _log('=============================================');
      _log('[ERROR-CONEXION] Fallo en etapa "$failedPhase"');
      _log('Dispositivo objetivo: "${device.name}" (${device.id})');
      _log('Duración hasta el fallo: $elapsedMs ms ($elapsedSec s)');
      _log('Excepción: $e');

      if (e is FlutterBluePlusException) {
        _log(
          'Detalles nativos: Código: ${e.code} | Descripción: ${e.description}',
        );
      }

      final errStr = e.toString();
      final isTimeout147 =
          errStr.contains('147') ||
          errStr.toLowerCase().contains('timeout') ||
          errStr.toLowerCase().contains('connection_timeout');

      if (isTimeout147) {
        _log('---------------------------------------------');
        _log(
          'DIAGNÓSTICO CRÍTICO: TIMEOUT GATT / CÓDIGO 147 (GATT_CONNECTION_TIMEOUT)',
        );
        _log(
          '1. VENTANA DE ANUNCIO CERRADA: El Tripper Pod original de Royal Enfield anuncia BLE únicamente durante los primeros 30 a 120 segundos tras girar la llave de la moto (contacto ON). Pasado ese tiempo apaga la radio BLE para ahorrar batería. SOLUCIÓN: Gira la llave a OFF y de nuevo a ON para reabrir la ventana publicitaria.',
        );
        _log(
          '2. LIMPIEZA DE VINCULACIÓN: Si el Samsung Galaxy A35 vinculó previamente el dispositivo "RE_DISP", ve a Ajustes de Android > Bluetooth > RE_DISP y selecciona "Desvincular" u "Olvidar".',
        );
        _log(
          '3. CONFLICTO DE APLICACIONES: Asegúrate de que la aplicación oficial de Royal Enfield esté completamente cerrada (Forzar detención) para que no bloquee el canal BLE.',
        );
        _log(
          '4. UBICACIÓN FÍSICA: Realiza la prueba junto a la moto estacionada, con la pantalla circular del Tripper encendida.',
        );
        _log('---------------------------------------------');
      }

      _log('=============================================');
      _isConnecting = false;
      return false;
    }
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _log(
      '[REstelar:BLE] [KEEPALIVE_TIMER_STARTED] Temporizador de supervisión activo (tick cada 1000 ms, umbral refresh 2200 ms).',
    );
    _keepAliveTimer = Timer.periodic(const Duration(milliseconds: 1000), (
      _,
    ) async {
      _log(
        '[REstelar:BLE] [KEEPALIVE_TIMER_TICK] Tick de supervisión ejecutado.',
      );
      if (_currentState.isReadyForNavigation && _writeCharacteristic != null) {
        final now = DateTime.now();
        final lastSent = _lastPacketSentTime;
        final msSinceLastTx = lastSent != null
            ? now.difference(lastSent).inMilliseconds
            : 999999;

        // Umbral de 2200 ms: garantiza que se envíe un paquete cada 2.2 - 3.2s,
        // otorgando margen amplio frente al watchdog de 5.0s del Tripper Pod.
        if (msSinceLastTx >= 2200) {
          if (_activeNavPacket != null) {
            _log(
              '[REstelar:BLE] [KEEPALIVE_TX_START] Motivo: Refresco pantalla navegación activa (delta=${msSinceLastTx}ms >= 2200ms)',
            );
            await _enqueuePacket(
              _activeNavPacket!,
              description:
                  'REFRESH_PANTALLA (${_activeNavDescription ?? "maniobra activa"})',
            );
          } else if (_isNavScreenActive) {
            final fallbackPacket = TripperProtocol.buildSafeTransitionPacket();
            _activeNavPacket = fallbackPacket;
            _activeNavDescription = 'REFRESH_SEGURIDAD_TRANSICION (0x1C)';
            _log(
              '[REstelar:BLE] [KEEPALIVE_TX_START] Motivo: Refresco transición 0x1C (delta=${msSinceLastTx}ms >= 2200ms)',
            );
            await _enqueuePacket(
              fallbackPacket,
              description: 'REFRESH_PANTALLA (seguridad transición 0x1C)',
            );
          } else {
            _log(
              '[REstelar:BLE] [KEEPALIVE_TX_START] Motivo: PING_FW reposo (delta=${msSinceLastTx}ms >= 2200ms)',
            );
            await _enqueuePacket(
              TripperProtocol.packetPingFw,
              description: 'PING_FW (watchdog keepalive reposo)',
            );
          }
        } else {
          _log(
            '[REstelar:BLE] [KEEPALIVE_SKIPPED] Transmisión omitida: delta=${msSinceLastTx}ms < 2200ms | Estado GATT: ${_currentState.name}',
          );
        }
      }
    });
  }

  Future<bool> _enqueuePacket(List<int> bytes, {required String description}) {
    // Si entra una instrucción de navegación o refresco, purgar de la cola refrescos o paquetes
    // obsoletos pendientes para evitar retraso acumulativo y contrapresión.
    final isNavOrRefresh =
        bytes.length == 20 &&
        ((bytes[0] == 0x10 && bytes[1] == 0x11) ||
            (bytes[0] == 0x03 && bytes[1] == 0x00));

    if (isNavOrRefresh) {
      _packetQueue.removeWhere((queued) {
        if (queued.description.startsWith('REFRESH_PANTALLA') ||
            queued.description.startsWith('PING_FW')) {
          queued.completer.complete(false);
          return true;
        }
        return false;
      });
    }

    final completer = Completer<bool>();
    _packetQueue.add(
      _QueuedPacket(
        bytes: bytes,
        description: description,
        completer: completer,
      ),
    );
    _log(
      '[REstelar:BLE] [BLE_QUEUE_STATE] Tamaño cola: ${_packetQueue.length} | Encolado: $description',
    );
    _pumpQueue();
    return completer.future;
  }

  void _clearQueue({required String reason}) {
    int cancelledCount = 0;
    for (final item in _packetQueue) {
      if (!item.completer.isCompleted) {
        item.completer.complete(false);
        cancelledCount++;
      }
    }
    _packetQueue.clear();
    _isProcessingQueue = false;
    if (cancelledCount > 0) {
      _log(
        '[REstelar:BLE] [BLE_QUEUE_PURGE] Cola vaciada ($reason): $cancelledCount paquetes cancelados.',
      );
    }
  }

  Future<void> _pumpQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_packetQueue.isNotEmpty) {
        final item = _packetQueue.removeAt(0);
        final char = _writeCharacteristic;
        if (char == null) {
          final msg =
              'Fallo de transmisión: No hay característica GATT activa.';
          _lastTransmissionResult = msg;
          _log('[REstelar:BLE] [TX-ERROR] ${item.description} | $msg');
          item.completer.complete(false);
          continue;
        }

        final hex = TripperProtocol.toHexString(item.bytes);
        final isNav =
            item.bytes.length == 20 &&
            item.bytes[0] == 0x10 &&
            item.bytes[1] == 0x11;
        final isKeepAlive =
            item.bytes.length == 20 &&
            item.bytes[0] == 0x03 &&
            item.bytes[1] == 0x00;

        if (isNav) {
          _log(
            '[REstelar:BLE] [NAV_PACKET_TX_START] ${item.description} | Trama: $hex',
          );
        } else {
          _log('[REstelar:BLE] [TX-START] ${item.description} | Trama: $hex');
        }

        final sw = Stopwatch()..start();

        try {
          _lastPacketSentHex = hex;
          final withoutResponse = char.properties.writeWithoutResponse;
          // Timeout estricto de 2000 ms: previene bloqueo permanente si Android demora el callback
          await char
              .write(item.bytes, withoutResponse: withoutResponse)
              .timeout(const Duration(milliseconds: 2000));
          sw.stop();
          _lastPacketSentTime = DateTime.now();

          if (isNav) {
            _lastNavPacketSentTime = _lastPacketSentTime;
            _lastNavPacketSentHex = hex;
            _log(
              '[REstelar:BLE] [NAV_PACKET_TX_COMPLETE] ${item.description} | Resultado: OK | Duración: ${sw.elapsedMilliseconds} ms | Trama: $hex',
            );
          } else if (isKeepAlive) {
            _lastKeepAliveSentTime = _lastPacketSentTime;
            _log(
              '[REstelar:BLE] [KEEPALIVE_TX_COMPLETE] ${item.description} | Resultado: OK | Duración: ${sw.elapsedMilliseconds} ms | Trama: $hex',
            );
          } else {
            _log(
              '[REstelar:BLE] [TX-COMPLETE] ${item.description} | Resultado: OK | Duración: ${sw.elapsedMilliseconds} ms | Trama: $hex',
            );
          }
          _lastTransmissionResult = 'OK (${item.description})';
          item.completer.complete(true);
        } on TimeoutException {
          sw.stop();
          final errMsg =
              'Timeout (2000 ms) en escritura GATT para ${item.description}';
          _lastTransmissionResult = errMsg;
          _log('[REstelar:BLE] [KEEPALIVE_TX_ERROR] [TX-TIMEOUT] $errMsg');
          item.completer.complete(false);
          // Pausa de seguridad para evitar colisión en el driver Bluetooth nativo
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (e) {
          sw.stop();
          final errMsg = 'Error al escribir en característica GATT: $e';
          _lastTransmissionResult = errMsg;
          _log(
            '[REstelar:BLE] [KEEPALIVE_TX_ERROR] [TX-ERROR] ${item.description} | Resultado: FALLO ($e) | Duración: ${sw.elapsedMilliseconds} ms',
          );
          item.completer.complete(false);
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    if (_writeCharacteristic == null) {
      _log('No se puede enviar trama: periférico no enlazado.');
      return false;
    }

    // Si la trama es de navegación (0x10 0x11), la marcamos como paquete activo para el bucle de refresco (watchdog 2s)
    if (bytes.length == 20 && bytes[0] == 0x10 && bytes[1] == 0x11) {
      final incomingHex = TripperProtocol.toHexString(bytes);
      final now = DateTime.now();
      _activeNavPacket = Uint8List.fromList(bytes);
      _activeNavDescription = 'TRAMA_CRUDA_PANTALLA (0x10 0x11)';
      _isNavScreenActive = true;

      // Deduplicación de ráfaga: si dos controladores (ej. Bridge y Diagnóstico) o notificaciones
      // redundantes solicitan escribir exactamente la misma trama 0x10 0x11 con menos de 400 ms de
      // diferencia, evitar escritura GATT duplicada.
      if (_lastNavPacketSentHex == incomingHex &&
          _lastNavPacketSentTime != null &&
          now.difference(_lastNavPacketSentTime!).inMilliseconds < 400) {
        return true;
      }
    } else if (bytes.length == 20 && bytes[0] == 0x50) {
      // Si es sincronización de hora (0x50), regresa a modo reloj
      _activeNavPacket = null;
      _isNavScreenActive = false;
      _isTestManeuverActive = false;
    }

    return _enqueuePacket(bytes, description: 'TRAMA_CRUDA_MANUAL');
  }

  @override
  Future<bool> sendTestMessage() async {
    if (_writeCharacteristic == null || !_currentState.isReadyForNavigation) {
      _log(
        'No se puede enviar indicación de prueba: periférico no enlazado o no autenticado.',
      );
      return false;
    }

    if (_isTestManeuverActive) {
      _log('Finalizando modo prueba de pantalla. Volviendo a modo reloj...');
      return stopNavigation();
    }

    _log(
      'Iniciando maniobra de prueba en pantalla: Recto 500m (con refresco watchdog cada 2s)...',
    );
    final testNav = TripperProtocol.buildNavPacket(
      maneuver: TripperProtocol.maneuverStraight,
      distanceMeters: 500,
      nextManeuver: TripperProtocol.nextManeuverNone,
    );
    _activeNavPacket = testNav;
    _activeNavDescription = 'PRUEBA_MANIOBRA_RECTO_500M';
    _isTestManeuverActive = true;
    _isNavScreenActive = true;

    final ok = await _enqueuePacket(
      testNav,
      description: 'PRUEBA_MANIOBRA_RECTO_500M',
    );
    if (ok) {
      _setState(TripperConnectionState.testMessageSent);
    }
    return ok;
  }

  @override
  Future<bool> stopNavigation() async {
    _log(
      '[NAV-STOP-REQ] Solicitud de detención de navegación manual recibida.',
    );

    final lastNavHex = _lastNavPacketSentHex;
    final lastNavTime = _lastNavPacketSentTime;

    // 1. Desactivar banderas de refresco de pantalla
    _activeNavPacket = null;
    _activeNavDescription = null;
    _isNavScreenActive = false;
    _isTestManeuverActive = false;

    // 2. Purgar de la cola cualquier trama de navegación (0x10 0x11) pendiente
    int purgedCount = 0;
    _packetQueue.removeWhere((item) {
      final isNav =
          item.bytes.length == 20 &&
          item.bytes[0] == 0x10 &&
          item.bytes[1] == 0x11;
      if (isNav) {
        purgedCount++;
        item.completer.complete(false);
        return true;
      }
      return false;
    });

    _log(
      '[NAV-STOP-PURGE] Refresco continuo de pantalla cancelado. '
      'Tramas de navegación purgadas de cola: $purgedCount. '
      'Última trama de navegación emitida: ${lastNavHex ?? "ninguna"} '
      '(${lastNavTime != null ? "${DateTime.now().difference(lastNavTime).inMilliseconds} ms atrás" : "N/A"}).',
    );

    if (_writeCharacteristic == null || !_currentState.isReadyForNavigation) {
      _log(
        '[NAV-STOP] Sesión BLE no activa o no lista. No se emite keepalive.',
      );
      return false;
    }

    // 3. Regresar al estado autenticado (enlace BLE activo en reposo)
    _setState(TripperConnectionState.authenticated);

    // 4. Salida formal y segura de la pantalla de navegación:
    // El firmware del Tripper Pod cuenta con un watchdog de pantalla de ~5s si está en modo 0x10 0x11.
    // Para retornar ordenadamente a la visualización del reloj nativo sin que el hardware aborte la conexión,
    // se emite un paquete formal de sincronización de hora (CMD_SET_TIME 0x50), seguido del keepalive de reposo PING_FW.
    _log(
      '[NAV-STOP-EXIT] Emitiendo CMD_SET_TIME para ordenar al Pod regresar al modo reloj nativo...',
    );
    final timePacket = TripperProtocol.buildSetTimeNowPacket();
    await _enqueuePacket(
      timePacket,
      description: 'CMD_SET_TIME (transición a reloj nativo post-navegación)',
    );

    _log(
      '[NAV-STOP-KEEPALIVE] Emitiendo PING_FW inmediato para mantener la conexión BLE en modo reposo...',
    );
    final pingOk = await _enqueuePacket(
      TripperProtocol.packetPingFw,
      description: 'PING_FW (mantenimiento enlace reposo post-navegación)',
    );

    _log(
      '[NAV-STOP-COMPLETE] Navegación detenida. Enlace BLE mantenido en reposo con reloj sincronizado y watchdog PING_FW cada 2s. '
      '(Resultado PING_FW inicial: ${pingOk ? "OK" : "FALLO"}).',
    );
    return true;
  }

  @override
  void clearActiveNavPacket({String? reason}) {
    if (_activeNavPacket != null) {
      _log(
        '[CLEAR_NAV] Limpiando trama activa de navegación (0x10 0x11): ${reason ?? "maniobra no transmitible / obsoleta"}.',
      );
      _activeNavPacket = null;
      _activeNavDescription = null;
      _isNavScreenActive = false;
      _isTestManeuverActive = false;
    }
  }

  void logAppLifecycleState(String lifecycleState) {
    _log(
      '[REstelar:LIFECYCLE] [APP_LIFECYCLE_STATE] Estado: $lifecycleState | GATT: ${_currentState.name} | Cola: ${_packetQueue.length}',
    );
  }

  @override
  Future<bool> sendPin(String pin) async {
    if (_writeCharacteristic == null) {
      _log('No se puede enviar PIN: periférico no enlazado.');
      return false;
    }
    final pinPacket = TripperProtocol.buildPinPacket(pin);
    return _enqueuePacket(pinPacket, description: 'PIN_AUTENTICACION');
  }

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async {
    if (!maneuver.isSupported) {
      _log(
        '[MANIOBRA-RECHAZADA] Maniobra desconocida o sin distancia válida (${maneuver.maneuverType.name}); no se envía trama al Tripper.',
      );
      clearActiveNavPacket(reason: 'Maniobra desconocida o no compatible');
      return false;
    }
    if (_writeCharacteristic == null || !_currentState.isReadyForNavigation) {
      _log('No se puede emitir maniobra: sesión Tripper Pod no autenticada.');
      return false;
    }

    _log(maneuver.toDiagnosticString());
    final bytes = maneuver.toProtocolPacket();
    _activeNavPacket = Uint8List.fromList(bytes);
    _activeNavDescription = maneuver.toDiagnosticString();
    _isNavScreenActive = true;
    _isTestManeuverActive = false;
    return _enqueuePacket(bytes, description: maneuver.toDiagnosticString());
  }

  Future<List<BluetoothService>> _discoverAndRecordServices(
    BluetoothDevice bleDevice,
    TripperDevice device,
  ) async {
    final stopwatch = Stopwatch()..start();
    final services = await bleDevice.discoverServices(
      subscribeToServicesChanged: false,
      timeout: 15,
    );
    stopwatch.stop();
    _log(
      'Servicios GATT descubiertos: ${services.length} (duración: ${stopwatch.elapsedMilliseconds} ms)',
    );

    _discoveredGattServices.clear();
    for (final service in services) {
      _log('-> Servicio UUID: ${service.uuid}');
      final charList = <TripperGattCharacteristic>[];
      for (final char in service.characteristics) {
        _log(
          '   -> Característica UUID: ${char.uuid} [Lectura: ${char.properties.read}, Escritura: ${char.properties.write}, WriteNoResp: ${char.properties.writeWithoutResponse}, Notificación: ${char.properties.notify}, Indicación: ${char.properties.indicate}]',
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
    return services;
  }

  @override
  Future<void> disconnect() async {
    _isLocalDisconnectRequested = true;
    _log(
      '[BLE-DISCONNECT-LOCAL-REQ] Solicitud local de desconexión BLE iniciada por el usuario o la aplicación.',
    );
    try {
      _setState(TripperConnectionState.disconnecting);
      _log('Desconectando dispositivo de forma segura...');
      _probeRetentionTimer?.cancel();
      _probeRetentionTimer = null;
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      _activeNavPacket = null;
      _isNavScreenActive = false;
      _isTestManeuverActive = false;
      _clearQueue(reason: 'Desconexión manual solicitada');
      _writeCharacteristic = null;
      await _activeBleDevice?.disconnect();
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _activeBleDevice = null;
      _connectedDevice = null;
      _connectedSince = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _currentConnectionPhase = null;
      _setState(TripperConnectionState.idle);
      _log('Desconexión completada.');
    } catch (e) {
      _log('Aviso al desconectar: $e');
      _probeRetentionTimer?.cancel();
      _probeRetentionTimer = null;
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      _activeNavPacket = null;
      _isNavScreenActive = false;
      _isTestManeuverActive = false;
      _clearQueue(reason: 'Desconexión manual con error');
      _writeCharacteristic = null;
      _connectedSince = null;
      _discoveredGattServices.clear();
      _gattServicesController.add(const []);
      _currentConnectionPhase = null;
      _setState(TripperConnectionState.idle);
    }
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
    buffer.writeln(
      'Estado de conexión: ${_currentState.name} (${_currentState.displayName})',
    );
    buffer.writeln('Fase de conexión: ${_currentConnectionPhase ?? "ninguna"}');
    buffer.writeln(
      'Tiempo conectado desde: ${_connectedSince?.toIso8601String() ?? "No conectado"}',
    );
    buffer.writeln('Contador de desconexiones: $_disconnectCount');
    buffer.writeln('Última etapa de error: ${_lastErrorStage ?? "ninguna"}');
    buffer.writeln('Último detalle de error: ${_lastErrorDetail ?? "ninguno"}');
    buffer.writeln('Última trama enviada: ${_lastPacketSentHex ?? "ninguna"}');
    buffer.writeln(
      'Última trama navegación: ${_lastNavPacketSentHex ?? "ninguna"} (${_lastNavPacketSentTime?.toIso8601String() ?? "N/A"})',
    );
    buffer.writeln(
      'Último keepalive (PING_FW): ${_lastKeepAliveSentTime?.toIso8601String() ?? "N/A"}',
    );
    buffer.writeln(
      'Desconexión local solicitada: $_isLocalDisconnectRequested',
    );
    buffer.writeln(
      'Resultado última transmisión: ${_lastTransmissionResult ?? "ninguno"}',
    );
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

/// Elemento encolado para transmisión serializada hacia la característica GATT del Tripper Pod.
class _QueuedPacket {
  final List<int> bytes;
  final String description;
  final Completer<bool> completer;

  _QueuedPacket({
    required this.bytes,
    required this.description,
    required this.completer,
  });
}
