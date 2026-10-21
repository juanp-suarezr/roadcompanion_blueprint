import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/tripper_connection_state.dart';
import '../../domain/entities/tripper_device.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../state/gpx_route_tracker.dart';
import '../widgets/background_tracking_info_dialog.dart';

/// Pantalla de laboratorio y diagnóstico experimental para GPS en segundo plano
/// y comunicación BLE con el Royal Enfield Tripper Pod.
class TripperDiagnosticScreen extends StatefulWidget {
  final GpxRouteTracker? activeTracker;
  final TripperBleService bleService;

  const TripperDiagnosticScreen({
    super.key,
    this.activeTracker,
    required this.bleService,
  });

  @override
  State<TripperDiagnosticScreen> createState() => _TripperDiagnosticScreenState();
}

class _TripperDiagnosticScreenState extends State<TripperDiagnosticScreen> {
  late TripperConnectionState _connectionState;
  List<TripperDevice> _devices = [];
  List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _connectionState = widget.bleService.currentState;
    _devices = List.from(widget.bleService.discoveredDevices);
    _logs = List.from(widget.bleService.diagnosticLogs);

    widget.bleService.stateStream.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });

    widget.bleService.discoveredDevicesStream.listen((devs) {
      if (mounted) setState(() => _devices = List.from(devs));
    });

    widget.bleService.diagnosticLogStream.listen((log) {
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
  }

  @override
  void dispose() {
    widget.activeTracker?.removeListener(_onTrackerUpdate);
    _logScrollController.dispose();
    super.dispose();
  }

  void _onTrackerUpdate() {
    if (mounted) setState(() {});
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
    final text = _logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnóstico técnico copiado al portapapeles.'),
        backgroundColor: AppColors.surfaceAccent,
        duration: Duration(seconds: 2),
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
        title: const Text(
          'Laboratorio Tripper & GPS',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.primaryGold),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGpsStatusSection(tracker),
            const SizedBox(height: 16),
            _buildBleSection(),
            const SizedBox(height: 16),
            _buildProtocolStagesSection(),
            const SizedBox(height: 16),
            _buildDiagnosticConsoleSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatusSection(GpxRouteTracker? tracker) {
    final bool isTracking = tracker?.isTracking ?? false;
    final int savedPoints = tracker?.recordedPositions.length ?? 0;
    final double? accuracy = tracker?.currentPosition?.accuracyMeters;
    final String accuracyStr =
        accuracy != null ? '±${accuracy.toStringAsFixed(1)} m' : 'Sin señal';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isTracking ? AppColors.primaryGold : AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.satellite_alt_rounded,
                color: isTracking ? AppColors.primaryGold : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Módulo GPS y Segundo Plano',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
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
                      : 'SOLO PRIMER PLANO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: (tracker?.isBackgroundEnabled ?? false)
                        ? AppColors.primaryGold
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                value: _formatDuration(tracker?.sessionDuration ?? Duration.zero),
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBleSection() {
    final bool isScanning = _connectionState == TripperConnectionState.scanning;
    final bool isConnected = _connectionState == TripperConnectionState.connected;

    return Container(
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.bluetooth_searching_rounded, color: AppColors.secondaryCyan, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Royal Enfield Tripper Pod (Meteor 350)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (isScanning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondaryCyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Enciende el switch de ignición de tu Meteor 350. El Tripper Pod circular entra en modo emparejamiento durante los primeros 120 segundos.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isScanning ? Colors.red.shade800 : AppColors.secondaryCyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isScanning ? Icons.stop_rounded : Icons.search_rounded, size: 18),
                label: Text(isScanning ? 'Detener escaneo' : 'Escanear BLE'),
                onPressed: () {
                  if (isScanning) {
                    widget.bleService.stopScan();
                  } else {
                    widget.bleService.startScan();
                  }
                },
              ),
              if (isConnected) const SizedBox(width: 10),
              if (isConnected)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.bluetooth_disabled_rounded, size: 18),
                  label: const Text('Desconectar'),
                  onPressed: () => widget.bleService.disconnect(),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isScanning
                    ? 'Buscando dispositivos Bluetooth cercanos...'
                    : 'No hay dispositivos detectados. Toca "Escanear BLE".',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            )
          else
            Column(
              children: _devices.map((d) => _buildDeviceItem(d)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(TripperDevice device) {
    final bool isThisConnected =
        widget.bleService.connectedDevice?.id == device.id &&
            _connectionState == TripperConnectionState.connected;

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
                        device.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (device.isTripperCandidate) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                const SizedBox(height: 2),
                Text(
                  'ID: ${device.id} | RSSI: ${device.rssi} dBm',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
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
                'ENLAZADO',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: () => widget.bleService.connect(device),
              child: const Text('Conectar', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
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
              const Icon(Icons.terminal_rounded, color: AppColors.primaryGold, size: 18),
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
                icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: AppColors.textSecondary),
                label: const Text('Limpiar', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, i) {
                      final log = _logs[i];
                      Color logColor = Colors.white70;
                      if (log.contains('CANDIDATO') || log.contains('VALIDADA')) {
                        logColor = AppColors.primaryGold;
                      } else if (log.contains('Error') || log.contains('desactivado')) {
                        logColor = Colors.redAccent;
                      } else if (log.contains('MANIOBRA')) {
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
        ],
      ),
    );
  }

  Widget _buildProtocolStagesSection() {
    final bool isConnected = _connectionState == TripperConnectionState.connected;
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
              Icon(Icons.checklist_rounded, color: AppColors.secondaryCyan, size: 18),
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
            title: 'Detección BLE',
            description: 'Escaneo pasivo/activo de balizas y filtrado de candidatos.',
            status: hasCandidates ? 'DETECTADO' : (_devices.isNotEmpty ? 'DISPOSITIVOS' : 'PENDIENTE'),
            isSuccess: _devices.isNotEmpty,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '2',
            title: 'Conexión GATT',
            description: 'Establecimiento del enlace y lectura de servicios/características.',
            status: isConnected ? 'ENLAZADO' : 'PENDIENTE',
            isSuccess: isConnected,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '3',
            title: 'Emparejamiento / Bonding PIN',
            description: 'Vinculación a nivel de sistema operativo Android con código numérico.',
            status: 'GESTIONADO POR ANDROID',
            isSuccess: isConnected,
          ),
          const Divider(color: Colors.white12, height: 16),
          _buildStageRow(
            stageNum: '4',
            title: 'Protocolo de Pantalla Tripper',
            description: 'Envío seguro de maniobras. Requiere protocolo certificado de RE.',
            status: 'MODO SEGURO ACTIVO',
            isSuccess: false,
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
                Icon(Icons.shield_outlined, color: AppColors.primaryGold, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'REstelar opera en modo de diagnóstico seguro no destructivo. No emite tramas de bytes especulativas ni altera la ECU o el velocímetro de la motocicleta.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (highlightColor ?? (isSuccess ? Colors.greenAccent : Colors.white24))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: highlightColor ?? (isSuccess ? Colors.greenAccent : Colors.white60),
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
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
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
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
