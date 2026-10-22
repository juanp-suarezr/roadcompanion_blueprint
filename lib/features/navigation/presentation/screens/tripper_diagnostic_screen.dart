import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../bridge/infrastructure/services/bridge_native_channel.dart';
import '../../../bridge/infrastructure/services/bridge_navigation_source.dart';
import '../../domain/entities/tripper_connection_state.dart';
import '../../domain/entities/tripper_device.dart';
import '../../domain/entities/tripper_gatt_info.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../domain/services/tripper_protocol.dart';
import '../../domain/services/voice_navigation_service.dart';
import '../../infrastructure/services/navigation_instruction_bridge.dart';
import '../state/gpx_route_tracker.dart';
import '../widgets/background_tracking_info_dialog.dart';

/// Pantalla de laboratorio y diagnóstico experimental para GPS en segundo plano,
/// audio TTS y comunicación BLE con el Royal Enfield Tripper Pod.
class TripperDiagnosticScreen extends StatefulWidget {
  final GpxRouteTracker? activeTracker;
  final TripperBleService bleService;
  final VoiceNavigationService? voiceService;
  final NavigationInstructionBridge? navigationBridge;
  final bool autoCheckHardware;

  const TripperDiagnosticScreen({
    super.key,
    this.activeTracker,
    required this.bleService,
    this.voiceService,
    this.navigationBridge,
    this.autoCheckHardware = true,
  });

  @override
  State<TripperDiagnosticScreen> createState() =>
      _TripperDiagnosticScreenState();
}

class _TripperDiagnosticScreenState extends State<TripperDiagnosticScreen> {
  late TripperConnectionState _connectionState;
  List<TripperDevice> _devices = [];
  List<TripperGattService> _gattServices = [];
  List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  // Estados de permisos y hardware
  bool _isCheckingPermissions = false;
  LocationPermission _locationPermission = LocationPermission.unableToDetermine;
  bool _isGpsServiceEnabled = false;
  bool _isBluetoothAvailable = false;
  PermissionStatus _bleScanStatus = PermissionStatus.denied;
  PermissionStatus _bleConnectStatus = PermissionStatus.denied;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BridgePermissionStatus _notificationPermissionStatus =
      BridgePermissionStatus.unknown;
  final BridgeNativeChannel _nativeChannel = BridgeNativeChannel();

  // Puente Waze / Maps -> Tripper
  late final NavigationInstructionBridge _bridge;
  bool _ownsBridge = false;
  StreamSubscription? _bridgeSub;
  Timer? _telemetryTimer;

  // Estado de voz
  bool _isTestingVoice = false;
  String? _voiceTestResult;
  String? _scanError;

  StreamSubscription? _stateSub;
  StreamSubscription? _devicesSub;
  StreamSubscription? _gattSub;
  StreamSubscription? _logSub;
  StreamSubscription? _adapterStateSub;
  StreamSubscription? _errorSub;

  @override
  void initState() {
    super.initState();
    _connectionState = widget.bleService.currentState;
    _devices = List.from(widget.bleService.discoveredDevices);
    _gattServices = List.from(widget.bleService.discoveredGattServices);
    _logs = List.from(widget.bleService.diagnosticLogs);
    _scanError = widget.bleService.lastScanError;

    if (widget.navigationBridge != null) {
      _bridge = widget.navigationBridge!;
      _ownsBridge = false;
    } else {
      _bridge = NavigationInstructionBridge(
        navigationSource: BridgeNavigationSource(nativeChannel: _nativeChannel),
        bleService: widget.bleService,
      );
      _ownsBridge = true;
    }

    _bridgeSub = _bridge.events.listen((_) {
      if (mounted) setState(() {});
    });

    _stateSub = widget.bleService.stateStream.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });

    _errorSub = widget.bleService.scanErrorStream.listen((err) {
      if (mounted) setState(() => _scanError = err);
    });

    _devicesSub = widget.bleService.discoveredDevicesStream.listen((devs) {
      if (mounted) setState(() => _devices = List.from(devs));
    });

    _gattSub = widget.bleService.discoveredGattServicesStream.listen((
      services,
    ) {
      if (mounted) setState(() => _gattServices = List.from(services));
    });

    _logSub = widget.bleService.diagnosticLogStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs = List.from(widget.bleService.diagnosticLogs);
        });
        _scrollToBottom();
      }
    });

    if (widget.activeTracker != null) {
      widget.activeTracker!.addListener(_onTrackerUpdate);
    }

    if (widget.autoCheckHardware) {
      try {
        _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
          if (mounted) setState(() => _adapterState = state);
        }, onError: (_) {});
      } catch (_) {}
      _bridge.start();
      _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && widget.bleService.connectedSince != null) {
          setState(() {});
        }
      });
      _refreshHardwareAndPermissions();
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _bridgeSub?.cancel();
    if (_ownsBridge) {
      _bridge.dispose();
    }
    _adapterStateSub?.cancel();
    _errorSub?.cancel();
    _stateSub?.cancel();
    _devicesSub?.cancel();
    _gattSub?.cancel();
    _logSub?.cancel();
    if (_connectionState == TripperConnectionState.scanning) {
      widget.bleService.stopScan();
    }
    widget.activeTracker?.removeListener(_onTrackerUpdate);
    _logScrollController.dispose();
    super.dispose();
  }

  void _onTrackerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshHardwareAndPermissions() async {
    if (!mounted) return;
    setState(() => _isCheckingPermissions = true);
    try {
      final gpsEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => false,
      );
      final locPerm = await Geolocator.checkPermission().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => LocationPermission.unableToDetermine,
      );
      final btAvail = await widget.bleService.isBluetoothAvailable().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => false,
      );

      PermissionStatus scanStatus = PermissionStatus.denied;
      PermissionStatus connectStatus = PermissionStatus.denied;
      try {
        scanStatus = await Permission.bluetoothScan.status.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => PermissionStatus.denied,
        );
        connectStatus = await Permission.bluetoothConnect.status.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => PermissionStatus.denied,
        );
      } catch (_) {}

      BluetoothAdapterState adState = BluetoothAdapterState.unknown;
      try {
        adState = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
      } catch (_) {}

      BridgePermissionStatus notifPerm = BridgePermissionStatus.unknown;
      try {
        notifPerm = await _nativeChannel.checkNotificationPermission().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => BridgePermissionStatus.unknown,
        );
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isGpsServiceEnabled = gpsEnabled;
          _locationPermission = locPerm;
          _isBluetoothAvailable = btAvail;
          _bleScanStatus = scanStatus;
          _bleConnectStatus = connectStatus;
          _adapterState = adState;
          _notificationPermissionStatus = notifPerm;
          _isCheckingPermissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingPermissions = false);
    }
  }

  Future<bool> _requestBlePermissions() async {
    if (!widget.autoCheckHardware) {
      if (mounted) {
        setState(() {
          _bleScanStatus = PermissionStatus.granted;
          _bleConnectStatus = PermissionStatus.granted;
        });
      }
      return true;
    }

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      final scanStatus =
          statuses[Permission.bluetoothScan] ?? PermissionStatus.denied;
      final connectStatus =
          statuses[Permission.bluetoothConnect] ?? PermissionStatus.denied;

      if (mounted) {
        setState(() {
          _bleScanStatus = scanStatus;
          _bleConnectStatus = connectStatus;
        });
      }

      final isGranted = scanStatus.isGranted && connectStatus.isGranted;
      if (!isGranted &&
          (scanStatus.isPermanentlyDenied ||
              connectStatus.isPermanentlyDenied) &&
          mounted) {
        _showBlePermanentlyDeniedDialog();
      }
      return isGranted;
    } catch (_) {
      return false;
    }
  }

  void _showBlePermanentlyDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Permisos Bluetooth Denegados',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'Android 16 requiere permisos de "Dispositivos cercanos" para descubrir y conectarse al Tripper Pod de tu Royal Enfield. Habilítalos en Ajustes.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGold,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text(
              'Abrir Ajustes',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStartBleScan() async {
    setState(() => _scanError = null);
    final bool hasPerm = await _requestBlePermissions();
    if (!hasPerm && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se requieren permisos de Dispositivos Cercanos para buscar el Tripper.',
          ),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final isAvail = await widget.bleService.isBluetoothAvailable();
    if (!isAvail) {
      if (widget.autoCheckHardware) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El Bluetooth está apagado. Enciéndelo para buscar dispositivos.',
            ),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    await widget.bleService.startScan();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyLogsToClipboard() {
    final report = widget.bleService.exportFullDiagnosticReport();
    final text = report.isNotEmpty ? report : _logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Informe de diagnóstico BLE copiado al portapapeles.'),
        backgroundColor: AppColors.surfaceAccent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleTestVoice() async {
    if (widget.voiceService == null) {
      setState(
        () =>
            _voiceTestResult = 'Servicio de voz no inyectado en esta pantalla.',
      );
      return;
    }

    setState(() {
      _isTestingVoice = true;
      _voiceTestResult = 'Reproduciendo locución de prueba en español...';
    });

    final success = await widget.voiceService!.testVoice(
      sampleText: 'REstelar: prueba de audio de navegación por voz exitosa.',
    );

    if (mounted) {
      setState(() {
        _isTestingVoice = false;
        _voiceTestResult = success
            ? 'Prueba emitida correctamente.'
            : 'Fallo al reproducir. Revisa si el motor de voz está instalado.';
      });
    }
  }

  bool _hasCode147Error() {
    final detail = widget.bleService.lastErrorDetail ?? '';
    final scanErr = _scanError ?? '';
    final stage = widget.bleService.lastErrorStage ?? '';
    return detail.contains('147') ||
        detail.contains('GATT_CONNECTION_TIMEOUT') ||
        scanErr.contains('147') ||
        stage.contains('147') ||
        _logs.any(
          (l) => l.contains('147') || l.contains('GATT_CONNECTION_TIMEOUT'),
        );
  }

  Future<void> _showPinDialog() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.pin_rounded, color: AppColors.primaryGold, size: 20),
            SizedBox(width: 8),
            Text(
              'PIN Tripper Pod',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Si tu Tripper Pod muestra un código numérico de 6 dígitos en la pantalla redonda durante la vinculación, ingrésalo aquí para autenticar la sesión BLE.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                color: AppColors.primaryGold,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.5),
                labelText: 'PIN de 6 dígitos',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                counterStyle: const TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primaryGold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGold,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Enviar PIN'),
          ),
        ],
      ),
    );

    if (pin != null && pin.isNotEmpty) {
      final success = await widget.bleService.sendPin(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'PIN de 6 dígitos enviado correctamente.'
                  : 'Fallo al enviar PIN al dispositivo.',
            ),
            backgroundColor: success ? Colors.green : AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildSafetyNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade600),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.two_wheeler_rounded,
            color: AppColors.primaryGold,
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONDICIONES DE PRUEBA FÍSICA SEGURA',
                  style: TextStyle(
                    color: AppColors.primaryGold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Realiza la sincronización con la motocicleta estacionada, ignición ON y el Tripper activo. REStelar opera en modo seguro sin modificar la ECU ni el velocímetro. No manipules el smartphone mientras conduces.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionTelemetryCard() {
    final dev = widget.bleService.connectedDevice;
    final isReady = _connectionState.isReadyForNavigation;
    final durationStr = widget.bleService.connectedSince != null
        ? _formatDuration(
            DateTime.now().difference(widget.bleService.connectedSince!),
          )
        : '00:00';
    final lastHex = widget.bleService.lastPacketSentHex ?? 'Ninguno';
    final lastRes = widget.bleService.lastTransmissionResult ?? 'Sin envíos';
    final lastStage = widget.bleService.lastErrorStage;
    final lastDetail = widget.bleService.lastErrorDetail;

    Color badgeColor;
    if (isReady) {
      badgeColor = Colors.greenAccent;
    } else if (_connectionState == TripperConnectionState.connecting ||
        _connectionState == TripperConnectionState.gattConnected ||
        _connectionState == TripperConnectionState.servicesDiscovered ||
        _connectionState == TripperConnectionState.characteristicIdentified ||
        _connectionState == TripperConnectionState.authPending) {
      badgeColor = AppColors.primaryGold;
    } else if (_connectionState == TripperConnectionState.error) {
      badgeColor = Colors.redAccent;
    } else {
      badgeColor = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Telemetría de Conexión BLE',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _connectionState.displayName.toUpperCase(),
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetricChip(
                label: 'Dispositivo',
                value: dev?.name ?? 'Sin enlace',
                icon: Icons.two_wheeler_rounded,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Dirección MAC',
                value: dev?.id ?? 'No enlazado',
                icon: Icons.fingerprint_rounded,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Señal RSSI',
                value: dev != null ? '${dev.rssi} dBm' : 'N/A',
                icon: Icons.signal_cellular_alt_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMetricChip(
                label: 'Enlace GATT',
                value:
                    (_connectionState == TripperConnectionState.gattConnected ||
                        isReady)
                    ? 'GATT ACTIVO'
                    : 'SIN CONEXIÓN',
                icon: Icons.link_rounded,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Servicios GATT',
                value: '${_gattServices.length} servicios',
                icon: Icons.account_tree_outlined,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Tiempo Enlace',
                value: durationStr,
                icon: Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Última trama enviada (20B HEX):',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      lastRes,
                      style: TextStyle(
                        color:
                            lastRes.contains('Aceptada') ||
                                lastRes.contains('OK')
                            ? Colors.greenAccent
                            : AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  lastHex,
                  style: const TextStyle(
                    color: AppColors.secondaryCyan,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lastStage != null || lastDetail != null) ...[
                  const Divider(color: Colors.white12, height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Etapa: ${lastStage ?? "N/A"} — ${lastDetail ?? ""}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCode147TroubleshootingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DIAGNÓSTICO: Timeout de Conexión GATT (Código 147)',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Causa confirmada en hardware: El Tripper Pod original de Royal Enfield únicamente emite anuncios BLE durante 30 a 120 segundos tras girar la llave a ON. Pasado ese tiempo, cualquier conexión finaliza en timeout 147.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Pasos de recuperación inmediata:',
            style: TextStyle(
              color: AppColors.primaryGold,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          _buildStepRow(
            '1',
            'Gira la llave de la moto a OFF y espera 3 segundos.',
          ),
          _buildStepRow(
            '2',
            'Gira la llave a ON nuevamente hasta ver la pantalla circular encendida.',
          ),
          _buildStepRow(
            '3',
            'Si RE_DISP quedó enlazado a medias, ve a Ajustes > Bluetooth de Android y toca "Desvincular / Olvidar".',
          ),
          _buildStepRow(
            '4',
            'Fuerza el cierre de la app oficial de Royal Enfield (para evitar conflicto de exclusividad BLE).',
          ),
          _buildStepRow(
            '5',
            'Toca "Buscar Tripper" en REStelar y pulsa "Conectar" inmediatamente.',
          ),
        ],
      ),
    );
  }

  Widget _buildManualTestingSection() {
    final bool isReady = _connectionState.isReadyForNavigation;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.send_rounded, color: AppColors.primaryGold, size: 18),
              SizedBox(width: 8),
              Text(
                'Pruebas de Intercambio Real con el Tablero',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Envía tramas certificadas de 20 bytes con CRC16 para verificar que el hardware del Tripper responde físicamente.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReady
                      ? AppColors.primaryGold
                      : Colors.white12,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: const Text(
                  'Enviar maniobra prueba (500m recto)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: isReady
                    ? () async {
                        final ok = await widget.bleService.sendTestMessage();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Maniobra de prueba enviada al Tripper Pod.'
                                    : 'Fallo al transmitir maniobra de prueba.',
                              ),
                              backgroundColor: ok
                                  ? Colors.green
                                  : AppColors.error,
                            ),
                          );
                        }
                      }
                    : null,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryCyan,
                  side: BorderSide(
                    color: isReady ? AppColors.secondaryCyan : Colors.white24,
                  ),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: const Text(
                  'Sincronizar reloj (CMD 0x50)',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: isReady
                    ? () async {
                        final now = DateTime.now();
                        final timePacket = TripperProtocol.buildSetTimePacket(
                          now.hour,
                          now.minute,
                          false,
                        );
                        final ok = await widget.bleService.sendRawPacket(
                          timePacket,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Comando de reloj 0x50 sincronizado con el Tripper.'
                                    : 'Error al enviar comando de hora.',
                              ),
                              backgroundColor: ok
                                  ? Colors.green
                                  : AppColors.error,
                            ),
                          );
                        }
                      }
                    : null,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGold,
                  side: const BorderSide(color: AppColors.primaryGold),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.pin_rounded, size: 16),
                label: const Text(
                  'Ingresar PIN / Handshake',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _showPinDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWazeBridgeMonitorSection() {
    final lastInst = _bridge.lastInstruction;
    final lastEvt = _bridge.lastEvent;
    final isGranted =
        _notificationPermissionStatus == BridgePermissionStatus.granted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.alt_route_rounded,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Monitor Waze → REStelar → Tripper',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _bridge.isListening
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _bridge.isListening
                        ? Colors.greenAccent
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  _bridge.isListening ? 'ESCUCHANDO' : 'DETENIDO',
                  style: TextStyle(
                    color: _bridge.isListening
                        ? Colors.greenAccent
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Captura notificaciones de navegación de Waze y Google Maps en segundo plano para transmitirlas al Tripper.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatusPill(
                label: 'Acceso Notificaciones',
                status: isGranted ? 'CONCEDIDO' : 'PENDIENTE',
                isOk: isGranted,
              ),
              if (!isGranted) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGold,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(
                    Icons.notifications_active_rounded,
                    size: 14,
                  ),
                  label: const Text(
                    'Conceder permiso',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () =>
                      _nativeChannel.openNotificationAccessSettings(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (lastInst == null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Inicia una ruta en Waze para ver las indicaciones capturadas aquí.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          lastInst.source.displayName,
                          style: const TextStyle(
                            color: AppColors.secondaryCyan,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        lastInst.distanceMeters != null
                            ? '${lastInst.distanceMeters!.round()} m'
                            : 'Sin distancia',
                        style: const TextStyle(
                          color: AppColors.primaryGold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lastInst.rawTitle ??
                        lastInst.destinationStreet ??
                        'Sin título',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (lastInst.rawText.isNotEmpty)
                    Text(
                      lastInst.rawText,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  const Divider(color: Colors.white12, height: 14),
                  Row(
                    children: [
                      const Text(
                        'Adaptación Tripper: ',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                      Text(
                        (lastEvt?.transmittedToTripper ?? false)
                            ? 'TRANSMITIDO A PANTALLA'
                            : (lastEvt?.adaptationResult.isSupported ?? false)
                            ? 'ESPERANDO CONEXIÓN BLE'
                            : (lastEvt != null
                                  ? 'NO COMPATIBLE'
                                  : 'PROCESANDO'),
                        style: TextStyle(
                          color: (lastEvt?.transmittedToTripper ?? false)
                              ? Colors.greenAccent
                              : AppColors.primaryGold,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (lastEvt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        lastEvt.adaptationResult.description,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracker = widget.activeTracker;

    return Scaffold(
      backgroundColor: AppColors.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCard,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conectar mi Tripper',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Laboratorio Tripper & GPS',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.primaryGold,
            ),
            tooltip: 'Información de Segundo Plano',
            onPressed: () => BackgroundTrackingInfoDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
            tooltip: 'Copiar diagnóstico',
            onPressed: _copyLogsToClipboard,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSafetyNoticeCard(),
            const SizedBox(height: 14),
            _buildHardwareAndPermissionsSection(),
            const SizedBox(height: 14),
            _buildConnectionTelemetryCard(),
            if (_hasCode147Error()) ...[
              const SizedBox(height: 14),
              _buildCode147TroubleshootingCard(),
            ],
            const SizedBox(height: 14),
            _buildGpsStatusSection(tracker),
            const SizedBox(height: 14),
            _buildBleSection(),
            const SizedBox(height: 14),
            _buildManualTestingSection(),
            const SizedBox(height: 14),
            _buildWazeBridgeMonitorSection(),
            const SizedBox(height: 14),
            _buildGattServicesSection(),
            const SizedBox(height: 14),
            _buildVoiceTestSection(),
            const SizedBox(height: 14),
            _buildProtocolStagesSection(),
            const SizedBox(height: 14),
            _buildDiagnosticConsoleSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareAndPermissionsSection() {
    final bool isLocGranted =
        _locationPermission == LocationPermission.whileInUse ||
        _locationPermission == LocationPermission.always;
    final bool isNotifGranted =
        _notificationPermissionStatus == BridgePermissionStatus.granted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.security_rounded,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Permisos y Sensores (Android 16)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isCheckingPermissions)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondaryCyan,
                  ),
                )
              else
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Actualizar estado',
                  onPressed: _refreshHardwareAndPermissions,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatusPill(
                label: 'GPS Físico',
                status: _isGpsServiceEnabled ? 'ENCENDIDO' : 'APAGADO',
                isOk: _isGpsServiceEnabled,
              ),
              const SizedBox(width: 8),
              _buildStatusPill(
                label: 'Ubicación',
                status: isLocGranted ? 'CONCEDIDO' : 'DENEGADO',
                isOk: isLocGranted,
              ),
              const SizedBox(width: 8),
              _buildStatusPill(
                label: 'Bluetooth',
                status: _isBluetoothAvailable ? 'DISPONIBLE' : 'INACTIVO',
                isOk: _isBluetoothAvailable,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatusPill(
                label: 'Notificaciones Waze',
                status: isNotifGranted ? 'CONCEDIDO' : 'PENDIENTE',
                isOk: isNotifGranted,
              ),
            ],
          ),
          if (!isLocGranted ||
              !_isGpsServiceEnabled ||
              !_isBluetoothAvailable ||
              !isNotifGranted) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!_isGpsServiceEnabled)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(
                      Icons.settings,
                      size: 14,
                      color: AppColors.primaryGold,
                    ),
                    label: const Text(
                      'Ajustes GPS',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryGold,
                      ),
                    ),
                    onPressed: () => Geolocator.openLocationSettings(),
                  ),
                if (!isLocGranted)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(
                      Icons.app_settings_alt,
                      size: 14,
                      color: AppColors.secondaryCyan,
                    ),
                    label: const Text(
                      'Ajustes App',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryCyan,
                      ),
                    ),
                    onPressed: () => Geolocator.openAppSettings(),
                  ),
                if (!isNotifGranted)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(
                      Icons.notifications_active_rounded,
                      size: 14,
                      color: AppColors.primaryGold,
                    ),
                    label: const Text(
                      'Permiso Notificaciones',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryGold,
                      ),
                    ),
                    onPressed: () =>
                        _nativeChannel.openNotificationAccessSettings(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    required String label,
    required String status,
    required bool isOk,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isOk
              ? Colors.greenAccent.withValues(alpha: 0.1)
              : Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOk
                ? Colors.greenAccent.withValues(alpha: 0.3)
                : Colors.redAccent.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: isOk ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatusSection(GpxRouteTracker? tracker) {
    final bool isTracking = tracker?.isTracking ?? false;
    final int savedPoints = tracker?.recordedPositions.length ?? 0;
    final double? accuracy = tracker?.currentPosition?.accuracyMeters;
    final String accuracyStr = accuracy != null
        ? '±${accuracy.toStringAsFixed(1)} m'
        : 'Sin señal';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTracking ? AppColors.primaryGold : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.satellite_alt_rounded,
                color: isTracking
                    ? AppColors.primaryGold
                    : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Módulo GPS y Seguimiento Satelital',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (tracker?.isBackgroundEnabled ?? false)
                      ? AppColors.primaryGold.withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (tracker?.isBackgroundEnabled ?? false)
                      ? 'SEGUNDO PLANO ACTIVO'
                      : 'PRIMER PLANO',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: (tracker?.isBackgroundEnabled ?? false)
                        ? AppColors.primaryGold
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetricChip(
                label: 'Precisión',
                value: accuracyStr,
                icon: Icons.gps_fixed_rounded,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Puntos Guardados',
                value: '$savedPoints',
                icon: Icons.pin_drop_rounded,
              ),
              const SizedBox(width: 8),
              _buildMetricChip(
                label: 'Duración',
                value: _formatDuration(
                  tracker?.sessionDuration ?? Duration.zero,
                ),
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPhaseLabel(String? phase) {
    switch (phase) {
      case 'deteniendo_escaneo':
        return 'Liberando radio...';
      case 'solicitando_enlace':
        return 'Enlazando...';
      case 'esperando_confirmacion':
        return 'Esperando conexión...';
      case 'descubriendo_servicios':
        return 'Leyendo GATT...';
      case 'conectado':
        return 'Conectado';
      case 'error':
        return 'Error de enlace';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Conectando...';
    }
  }

  String _getAdapterStateLabel() {
    switch (_adapterState) {
      case BluetoothAdapterState.on:
        return 'Encendido';
      case BluetoothAdapterState.off:
        return 'Apagado';
      case BluetoothAdapterState.unavailable:
        return 'No disponible';
      case BluetoothAdapterState.unauthorized:
        return 'Sin autorización';
      default:
        return 'Verificando...';
    }
  }

  Color _getAdapterStateColor() {
    switch (_adapterState) {
      case BluetoothAdapterState.on:
        return Colors.greenAccent;
      case BluetoothAdapterState.off:
        return Colors.orangeAccent;
      case BluetoothAdapterState.unavailable:
        return Colors.redAccent;
      case BluetoothAdapterState.unauthorized:
        return Colors.redAccent;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getPermissionsLabel() {
    if (_bleScanStatus.isGranted && _bleConnectStatus.isGranted) {
      return 'Concedidos';
    }
    if (_bleScanStatus.isPermanentlyDenied ||
        _bleConnectStatus.isPermanentlyDenied) {
      return 'Denegados (Ajustes)';
    }
    if (_bleScanStatus.isDenied || _bleConnectStatus.isDenied) {
      return 'Denegados';
    }
    return 'Pendientes';
  }

  Color _getPermissionsColor() {
    if (_bleScanStatus.isGranted && _bleConnectStatus.isGranted) {
      return Colors.greenAccent;
    }
    if (_bleScanStatus.isPermanentlyDenied ||
        _bleConnectStatus.isPermanentlyDenied) {
      return Colors.redAccent;
    }
    if (_bleScanStatus.isDenied || _bleConnectStatus.isDenied) {
      return Colors.orangeAccent;
    }
    return AppColors.textSecondary;
  }

  Widget _buildStepRow(String stepNumber, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryGold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: AppColors.primaryGold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDeviceState(bool isScanning) {
    if (isScanning) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.secondaryCyan,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Buscando todos los periféricos BLE cercanos sin filtros...',
                style: TextStyle(color: AppColors.secondaryCyan, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primaryGold,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Sin dispositivos detectados',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Pasos para conectar tu Tripper Pod:',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildStepRow(
            '1',
            'Gira la llave de ignición de tu Meteor 350 a la posición ON.',
          ),
          _buildStepRow(
            '2',
            'Observa que la pantalla circular del Tripper encienda.',
          ),
          _buildStepRow(
            '3',
            'Toca "Buscar Tripper" (el Tripper anuncia BLE durante los primeros 120 segundos).',
          ),
        ],
      ),
    );
  }

  Widget _buildBleSection() {
    final bool isScanning = _connectionState == TripperConnectionState.scanning;
    final bool isConnected =
        _connectionState == TripperConnectionState.connected;
    final bool isConnecting =
        _connectionState == TripperConnectionState.connecting;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bluetooth_searching_rounded,
                color: AppColors.secondaryCyan,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conectar mi Tripper',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Royal Enfield Tripper Pod (Meteor 350)',
                      style: TextStyle(
                        color: AppColors.primaryGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondaryCyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Enciende la moto y el Tripper para buscar dispositivos cercanos.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          // Estado de Adaptador y Permisos
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getAdapterStateColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getAdapterStateColor().withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bluetooth_rounded,
                      size: 14,
                      color: _getAdapterStateColor(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bluetooth: ${_getAdapterStateLabel()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getAdapterStateColor(),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getPermissionsColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getPermissionsColor().withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.security_rounded,
                      size: 14,
                      color: _getPermissionsColor(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Permisos BLE: ${_getPermissionsLabel()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getPermissionsColor(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Botones de acción principales
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isScanning
                        ? Colors.red.shade800
                        : AppColors.secondaryCyan,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: Icon(
                    isScanning ? Icons.stop_rounded : Icons.search_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isScanning ? 'Cancelar búsqueda' : 'Buscar Tripper',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    if (isScanning) {
                      widget.bleService.stopScan();
                    } else {
                      _handleStartBleScan();
                    }
                  },
                ),
              ),
              if (isConnected || isConnecting) const SizedBox(width: 10),
              if (isConnected || isConnecting)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bluetooth_disabled_rounded, size: 16),
                  label: const Text(
                    'Desconectar',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () => widget.bleService.disconnect(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondaryCyan,
              side: BorderSide(
                color: AppColors.secondaryCyan.withValues(alpha: 0.5),
              ),
              minimumSize: const Size.fromHeight(38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text(
              'Copiar Informe Técnico BLE Completo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: _copyLogsToClipboard,
          ),
          if (_scanError != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _scanError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _scanError = null),
                  ),
                ],
              ),
            ),
          ],
          if (_devices.isEmpty)
            _buildEmptyDeviceState(isScanning)
          else ...[
            Row(
              children: [
                Text(
                  'Dispositivos encontrados (${_devices.length})',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (isScanning) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.secondaryCyan,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Actualizando en vivo...',
                    style: TextStyle(
                      color: AppColors.secondaryCyan,
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.greenAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Búsqueda finalizada',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Column(children: _devices.map((d) => _buildDeviceItem(d)).toList()),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceItem(TripperDevice device) {
    final bool isThisConnected =
        widget.bleService.connectedDevice?.id == device.id &&
        _connectionState == TripperConnectionState.connected;
    final bool isThisConnecting =
        widget.bleService.connectedDevice?.id == device.id &&
        _connectionState == TripperConnectionState.connecting;

    final bool isUnnamed =
        device.name.trim().isEmpty ||
        device.name == 'Dispositivo BLE sin nombre';
    final String effectiveName = isUnnamed
        ? 'Dispositivo BLE sin nombre'
        : device.name.trim();
    final String effectiveId = device.id.trim().isEmpty
        ? 'ID no disponible'
        : device.id.trim();

    Color rssiColor;
    if (device.rssi >= -65) {
      rssiColor = Colors.greenAccent;
    } else if (device.rssi >= -80) {
      rssiColor = AppColors.primaryGold;
    } else {
      rssiColor = Colors.orangeAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: device.isTripperCandidate
            ? AppColors.primaryGold.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: device.isTripperCandidate
              ? AppColors.primaryGold.withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            device.isTripperCandidate
                ? Icons.two_wheeler_rounded
                : Icons.bluetooth_rounded,
            color: device.isTripperCandidate
                ? AppColors.primaryGold
                : AppColors.textSecondary,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        effectiveName,
                        style: TextStyle(
                          color: isUnnamed
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: isUnnamed
                              ? FontWeight.normal
                              : FontWeight.bold,
                          fontStyle: isUnnamed
                              ? FontStyle.italic
                              : FontStyle.normal,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (device.isTripperCandidate) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'CANDIDATO TRIPPER (${device.confidenceLevel})',
                          style: const TextStyle(
                            color: AppColors.primaryGold,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'ID: $effectiveId',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '•',
                      style: TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.signal_cellular_alt_rounded,
                      size: 12,
                      color: rssiColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${device.rssi} dBm',
                      style: TextStyle(
                        color: rssiColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (device.technicalEvidence.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    device.technicalEvidence,
                    style: TextStyle(
                      color: device.isTripperCandidate
                          ? AppColors.primaryGold.withValues(alpha: 0.9)
                          : Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isThisConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade900.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: const Text(
                'CONECTADO',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (isThisConnecting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primaryGold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.primaryGold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getPhaseLabel(
                          widget.bleService.currentConnectionPhase,
                        ),
                        style: const TextStyle(
                          color: AppColors.primaryGold,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Cancelar conexión',
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.bleService.cancelPendingConnection(),
                ),
              ],
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: device.isTripperCandidate
                    ? AppColors.primaryGold
                    : Colors.white12,
                foregroundColor: device.isTripperCandidate
                    ? AppColors.backgroundBlack
                    : AppColors.textPrimary,
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              onPressed: widget.bleService.isConnecting
                  ? null
                  : () => widget.bleService.connect(device),
              child: const Text('Conectar', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildGattServicesSection() {
    final bool isConnected =
        _connectionState == TripperConnectionState.connected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Servicios y Características GATT',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                isConnected
                    ? '${_gattServices.length} servicios'
                    : 'Sin enlace',
                style: TextStyle(
                  fontSize: 11,
                  color: isConnected
                      ? Colors.greenAccent
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Conecta un dispositivo BLE para inspeccionar su árbol de servicios, UUIDs y permisos.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            )
          else if (_gattServices.isEmpty)
            const Text(
              'Leyendo servicios GATT del dispositivo...',
              style: TextStyle(color: AppColors.primaryGold, fontSize: 11.5),
            )
          else
            Column(
              children: _gattServices.map((service) {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servicio UUID: ${service.uuid}',
                        style: const TextStyle(
                          color: AppColors.secondaryCyan,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...service.characteristics.map((char) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Text(
                            '• Char: ${char.uuid}\n  [${char.propertiesSummary}]',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceTestSection() {
    final vs = widget.voiceService;
    final status = vs?.status ?? VoiceServiceStatus.uninitialized;
    final statusStr = _formatVoiceStatus(status);
    final statusColor = _getVoiceStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_rounded,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Motor de Voz TTS (Indicaciones de Casco)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusStr,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            vs?.statusMessage ??
                'Permite verificar que el sintetizador pronuncie español correctamente antes de salir a carretera.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryCyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _isTestingVoice
                      ? Icons.hourglass_top_rounded
                      : Icons.volume_up_rounded,
                  size: 16,
                ),
                label: Text(
                  _isTestingVoice ? 'Probando...' : 'Probar voz',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isTestingVoice ? null : _handleTestVoice,
              ),
              if (vs != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: vs.isMuted
                        ? Colors.white70
                        : AppColors.secondaryCyan,
                    side: BorderSide(
                      color: vs.isMuted
                          ? Colors.white24
                          : AppColors.secondaryCyan,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    vs.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 16,
                  ),
                  label: Text(
                    vs.isMuted ? 'Desilenciar' : 'Silenciar',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    setState(() {
                      vs.toggleMute();
                    });
                  },
                ),
              ],
            ],
          ),
          if (_voiceTestResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _voiceTestResult!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primaryGold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatVoiceStatus(VoiceServiceStatus s) {
    switch (s) {
      case VoiceServiceStatus.uninitialized:
        return 'Sin inicializar';
      case VoiceServiceStatus.initializing:
        return 'Inicializando voz';
      case VoiceServiceStatus.ready:
        return 'Voz lista';
      case VoiceServiceStatus.muted:
        return 'Voz silenciada';
      case VoiceServiceStatus.error:
        return 'Error de voz';
    }
  }

  Color _getVoiceStatusColor(VoiceServiceStatus s) {
    switch (s) {
      case VoiceServiceStatus.ready:
        return Colors.greenAccent;
      case VoiceServiceStatus.muted:
        return AppColors.primaryGold;
      case VoiceServiceStatus.initializing:
        return AppColors.secondaryCyan;
      case VoiceServiceStatus.error:
        return Colors.redAccent;
      case VoiceServiceStatus.uninitialized:
        return Colors.white54;
    }
  }

  Widget _buildProtocolStagesSection() {
    final bool isConnected =
        _connectionState == TripperConnectionState.connected;
    final bool hasCandidates = _devices.any((d) => d.isTripperCandidate);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                color: AppColors.secondaryCyan,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Fases de Validación — Royal Enfield Tripper',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStageRow(
            stageNum: '1',
            title: 'Detección BLE (RE_DISP)',
            description:
                'Identificación de RE_DISP, prefijo OUI NXP 00:60:37 y servicio 01FF0100.',
            status: hasCandidates
                ? 'DETECTADO'
                : (_devices.isNotEmpty ? 'DISPOSITIVOS' : 'PENDIENTE'),
            isSuccess: _devices.isNotEmpty,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '2',
            title: 'Conexión GATT (Wireless UART)',
            description:
                'Enlace GATT sobre servicio 01ff0100 y característica 01ff0101.',
            status: isConnected ? 'ENLAZADO' : 'PENDIENTE',
            isSuccess: isConnected,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '3',
            title: 'Handshake, Reloj & Keepalive',
            description:
                'Trama resume (0x21 0x00), ajuste horario (0x50) y latido periódico cada 2s (0x03).',
            status: _connectionState.isReadyForNavigation
                ? 'ACTIVO (VERIFICADO)'
                : 'PENDIENTE',
            isSuccess: _connectionState.isReadyForNavigation,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '4',
            title: 'Protocolo de Navegación 20B',
            description:
                'Envío de maniobras (0x10 0x11), distancias y ETA con CRC16/CCITT-FALSE verificado.',
            status: widget.bleService.lastTransmissionResult != null
                ? 'TRANSMISIÓN PROBADA'
                : 'LISTO PARA ENVÍO',
            isSuccess: widget.bleService.lastTransmissionResult != null,
            highlightColor: AppColors.primaryGold,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: AppColors.primaryGold,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'REstelar opera en modo de diagnóstico seguro no destructivo. No emite tramas de bytes especulativas ni altera la ECU o el velocímetro de la motocicleta.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageRow({
    required String stageNum,
    required String title,
    required String description,
    required String status,
    required bool isSuccess,
    Color? highlightColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSuccess
                ? Colors.greenAccent.withValues(alpha: 0.2)
                : Colors.white10,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSuccess ? Colors.greenAccent : Colors.white24,
            ),
          ),
          child: Text(
            stageNum,
            style: TextStyle(
              color: isSuccess ? Colors.greenAccent : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (highlightColor ??
                                  (isSuccess
                                      ? Colors.greenAccent
                                      : Colors.white24))
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color:
                            highlightColor ??
                            (isSuccess ? Colors.greenAccent : Colors.white60),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticConsoleSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.terminal_rounded,
                color: AppColors.primaryGold,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Consola de Diagnóstico en Vivo',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                label: const Text(
                  'Limpiar',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                onPressed: () => widget.bleService.clearDiagnosticLogs(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 180,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: _logs.isEmpty
                ? const Text(
                    'Esperando eventos de navegación y Bluetooth...',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, i) {
                      final log = _logs[i];
                      Color logColor = Colors.white70;
                      if (log.contains('CANDIDATO') ||
                          log.contains('VALIDADA')) {
                        logColor = AppColors.primaryGold;
                      } else if (log.contains('Error') ||
                          log.contains('desactivado')) {
                        logColor = Colors.redAccent;
                      } else if (log.contains('MANIOBRA') ||
                          log.contains('UUID')) {
                        logColor = AppColors.secondaryCyan;
                      }
                      return Text(
                        log,
                        style: TextStyle(
                          color: logColor,
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text(
                'Copiar diagnóstico completo al portapapeles',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: _copyLogsToClipboard,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
