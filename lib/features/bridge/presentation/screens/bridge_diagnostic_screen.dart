import 'package:flutter/material.dart';
import '../../../../app/state/app_settings_state.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../../navigation/domain/services/navigation_source.dart';
import '../../../navigation/infrastructure/services/flutter_blue_plus_tripper_service.dart';
import '../../domain/entities/bridge_instruction_status.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../infrastructure/services/bridge_native_channel.dart';
import '../state/bridge_diagnostic_controller.dart';

/// Pantalla de Modo Compañero y diagnóstico técnico para ESTELA Bridge.
///
/// Permite al motociclista verificar en tiempo real:
/// 1. Selección de fuente del viaje (Waze, Google Maps o Interno).
/// 2. Separación explícita entre Fuente seleccionada, Fuente activa del viaje,
///    Última fuente que emitió un evento y Estado de navegación.
/// 3. El estado del permiso del sistema Android (Notification Listener) con refresco en `onResume`.
/// 4. La disponibilidad de geometría vial y detección de curvas según la fuente activa.
/// 5. La extracción de maniobras, distancias, calles, extras, RemoteViews y trazabilidad correlacionada.
class BridgeDiagnosticScreen extends StatefulWidget {
  final BridgeDiagnosticController? controller;

  const BridgeDiagnosticScreen({super.key, this.controller});

  @override
  State<BridgeDiagnosticScreen> createState() => _BridgeDiagnosticScreenState();
}

class _BridgeDiagnosticScreenState extends State<BridgeDiagnosticScreen>
    with WidgetsBindingObserver {
  late final BridgeDiagnosticController _controller;
  bool _isInternalController = false;
  bool _didInitializeController = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = BridgeDiagnosticController(
        bleService: FlutterBluePlusTripperService(),
        strictSourceFilter: true,
      );
      _isInternalController = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SelectedNavigationSourceType? scopedSource;
    try {
      final scope = context
          .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
      scopedSource = scope?.notifier?.selectedNavigationSource;
    } catch (_) {}

    if (!_didInitializeController) {
      _didInitializeController = true;
      _controller.initialize(
        initialTripSource: scopedSource,
        strictFilter: _isInternalController ? true : null,
      );
      return;
    }

    if (scopedSource != null && _controller.selectedSource != scopedSource) {
      _controller.selectNavigationSource(scopedSource, strictFilter: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isInternalController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.nightBlue,
          appBar: AppBar(
            backgroundColor: AppColors.surfaceNavy,
            elevation: 0,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnóstico ESTELA Bridge',
                  style: TextStyle(
                    color: AppColors.coldWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Google Maps & Waze -> Tripper',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Actualizar permiso y sincronizar notificaciones',
                icon: const Icon(Icons.refresh, color: AppColors.cyanLuminous),
                onPressed: () => _controller.checkPermission(),
              ),
              IconButton(
                tooltip: 'Limpiar sesión',
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _controller.clearSession(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildPermissionBanner(context),
              const SizedBox(height: 16),
              _buildListeningStatusCard(),
              const SizedBox(height: 16),
              _buildLatestInstructionSection(),
              const SizedBox(height: 16),
              _buildAutoSourceStatusCard(),
              const SizedBox(height: 16),
              _buildGeometryAndCurvesStatusCard(),
              const SizedBox(height: 16),
              _buildCorrelatedTraceSection(),
              const SizedBox(height: 16),
              _buildHistorySection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAutoSourceStatusCard() {
    final activeSourceText = _controller.activeSourceDisplayName;
    final lastInstruction = _controller.lastInstruction;
    final lastInstructionText =
        (lastInstruction != null &&
            lastInstruction.isCompatibleWithTripper &&
            !lastInstruction.isStale)
        ? '${lastInstruction.maneuverType.name}${lastInstruction.distanceMeters != null ? " • ${lastInstruction.distanceMeters} m" : ""}${lastInstruction.destinationStreet != null ? " hacia ${lastInstruction.destinationStreet}" : ""}'
        : (lastInstruction != null && lastInstruction.isStale
              ? 'Ruta finalizada o cancelada'
              : (lastInstruction?.isAppRunningNotification == true
                    ? 'App en ejecución (sin maniobra)'
                    : 'Sin instrucción de giro activa'));

    final lastInstructionTime = lastInstruction != null
        ? lastInstruction.receivedAt.toIso8601String().substring(11, 19)
        : '--:--:--';

    final nativeListenerStatus = _controller.isListening
        ? 'Escucha activa (Android)'
        : 'Inactiva';

    final tripperBleStatus = _controller.lastTransmittedToTripper
        ? 'Sincronizado / Transmitiendo'
        : 'Conectado a BLE / En espera';

    final navigationStateText = _controller.companionState.displayName;

    Color activeSourceColor = AppColors.secondaryText;
    if (activeSourceText == 'Waze') {
      activeSourceColor = const Color(0xFF33CCFF);
    } else if (activeSourceText == 'Google Maps') {
      activeSourceColor = const Color(0xFF4285F4);
    } else if (activeSourceText == 'RoadCompanion Interno') {
      activeSourceColor = AppColors.cyanLuminous;
    }

    return Container(
      key: const ValueKey('auto_source_mode_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.cyanLuminous.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cyanLuminous.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.cyanLuminous,
                      size: 14,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'MODO DE FUENTE: AUTO',
                      style: TextStyle(
                        color: AppColors.cyanLuminous,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cardNavy,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Filtro: Maps | Waze',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.nightBlue,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardNavy),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAutoInfoRow(
                  'Fuente activa',
                  activeSourceText,
                  valueColor: activeSourceColor,
                  isBold: true,
                ),
                const SizedBox(height: 6),
                _buildAutoInfoRow(
                  'Última instrucción',
                  lastInstructionText,
                  valueColor: AppColors.coldWhite,
                ),
                const SizedBox(height: 6),
                _buildAutoInfoRow(
                  'Hora instrucción',
                  lastInstructionTime,
                  valueColor: AppColors.secondaryText,
                ),
                const SizedBox(height: 6),
                _buildAutoInfoRow(
                  'Escucha nativa',
                  nativeListenerStatus,
                  valueColor: _controller.isListening
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(height: 6),
                _buildAutoInfoRow(
                  'Conexión Tripper',
                  tripperBleStatus,
                  valueColor: _controller.lastTransmittedToTripper
                      ? AppColors.cyanLuminous
                      : AppColors.secondaryText,
                ),
                const SizedBox(height: 6),
                _buildAutoInfoRow(
                  'Estado navegación',
                  navigationStateText,
                  valueColor: AppColors.coldWhite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoInfoRow(
    String label,
    String value, {
    Color valueColor = AppColors.coldWhite,
    bool isBold = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeometryAndCurvesStatusCard() {
    final caps = _controller.sourceCapabilities;
    final hasGeom = caps.providesRoadGeometry;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasGeom
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.warning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasGeom ? Icons.timeline_rounded : Icons.info_outline_rounded,
            color: hasGeom ? AppColors.success : AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasGeom
                      ? 'Geometría vial y curvas: VERIFICADA (OSRM/GPX)'
                      : 'Geometría vial y curvas: NO EXPUESTA POR NAVEGADOR EXTERNO',
                  style: TextStyle(
                    color: hasGeom ? AppColors.success : AppColors.warning,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  caps.limitationDisclosure,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final status = _controller.permissionStatus;
    final isGranted = status == BridgePermissionStatus.granted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isGranted
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted ? AppColors.success : AppColors.warning,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                color: isGranted ? AppColors.success : AppColors.warning,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isGranted
                      ? 'Acceso a Notificaciones: CONCEDIDO'
                      : 'Acceso a Notificaciones: PENDIENTE',
                  style: TextStyle(
                    color: isGranted ? AppColors.success : AppColors.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'ESTELA captura de forma local las indicaciones de navegación de Google Maps y Waze. '
            'Los datos nunca salen de tu dispositivo y no se guardan de forma permanente.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyanLuminous,
                  foregroundColor: AppColors.nightBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text(
                  'Activar en Ajustes de Android',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => _controller.openSettings(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListeningStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _controller.isListening
                      ? AppColors.cyanLuminous
                      : AppColors.inactive,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _controller.isListening
                    ? 'Escucha nativa activa'
                    : 'Escucha inactiva',
                style: const TextStyle(
                  color: AppColors.coldWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Filtro: ${_controller.activeFilterLabel}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (_controller.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _controller.errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLatestInstructionSection() {
    final instruction = _controller.lastInstruction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ÚLTIMA INSTRUCCIÓN PROCESADA',
          style: TextStyle(
            color: AppColors.cyanLuminous,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        if (instruction == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceNavy,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardNavy),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.navigation_outlined,
                  size: 40,
                  color: AppColors.secondaryText,
                ),
                SizedBox(height: 10),
                Text(
                  'Sin indicaciones capturadas en esta sesión',
                  style: TextStyle(
                    color: AppColors.coldWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Inicia una ruta en Google Maps o Waze para observar el flujo de maniobras.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          _buildInstructionCard(instruction),
      ],
    );
  }

  Widget _buildInstructionCard(BridgeNavigationInstruction instruction) {
    final statusColor = _getStatusColor(instruction.status);
    final statusLabel = instruction.status.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSourceBadge(instruction.source),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.cardNavy, height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildManeuverIcon(instruction.maneuverType),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getManeuverTitle(instruction),
                      style: const TextStyle(
                        color: AppColors.coldWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (instruction.destinationStreet != null)
                      Text(
                        'Vía: ${instruction.destinationStreet!}',
                        style: const TextStyle(
                          color: AppColors.electricBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (instruction.roundaboutExit != null)
                      Text(
                        'Toma la ${instruction.roundaboutExit}ª salida',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 13,
                        ),
                      ),
                    if (instruction.discardReason != null)
                      Text(
                        instruction.discardReason!,
                        style: TextStyle(
                          color: instruction.isAppRunningNotification
                              ? AppColors.secondaryText
                              : AppColors.warning,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
              if (instruction.distanceMeters != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.nightBlue,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardNavy),
                  ),
                  child: Text(
                    instruction.distanceMeters! >= 1000
                        ? '${(instruction.distanceMeters! / 1000).toStringAsFixed(1)} km'
                        : '${instruction.distanceMeters} m',
                    style: const TextStyle(
                      color: AppColors.cyanLuminous,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.nightBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TEXTO CRUDO CAPTURADO (Inspección local):',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instruction.rawText.isNotEmpty
                      ? instruction.rawText
                      : (instruction.isEmptyNotification
                            ? '(Notificación recibida sin texto extraíble en Android)'
                            : '(Sin texto disponible)'),
                  style: const TextStyle(
                    color: AppColors.coldWhite,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Paquete: ${instruction.source.packageName.isNotEmpty ? instruction.source.packageName : instruction.source.displayName}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                if (instruction.notificationKey != null ||
                    instruction.notificationCategory != null)
                  Text(
                    'Notificación: key=${instruction.notificationKey ?? "n/a"} | cat=${instruction.notificationCategory ?? "n/a"}',
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                Text(
                  'Extras: ${instruction.availableExtras.isEmpty ? "(no reportados)" : instruction.availableExtras.join(", ")}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'RemoteViews: ${instruction.remoteViewsTexts.isEmpty ? "(sin textos adicionales)" : instruction.remoteViewsTexts.join(" | ")}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'Decisión: ${instruction.isCompatibleWithTripper ? "ACEPTADO -> Maniobra ${instruction.maneuverType.name} (${instruction.distanceMeters ?? 0} m)" : "DESCARTADO -> ${instruction.discardReason ?? instruction.status.name}"}',
                  style: TextStyle(
                    color: instruction.isCompatibleWithTripper
                        ? AppColors.success
                        : AppColors.warning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hora: ${instruction.receivedAt.toIso8601String().substring(11, 19)}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrelatedTraceSection() {
    final traces = NavigationDiagnosticLogger.getCorrelatedEntries();
    if (traces.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRAZABILIDAD CORRELACIONADA POR EVENTO',
                style: TextStyle(
                  color: AppColors.cyanLuminous,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${traces.length} pasos',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...traces
              .take(8)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    entry.format(),
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final historyItems = _controller.historyItems;
    final fallbackHistory = _controller.sessionHistory;
    final count = historyItems.isNotEmpty
        ? historyItems.length
        : fallbackHistory.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'HISTORIAL DE LA SESIÓN',
              style: TextStyle(
                color: AppColors.cyanLuminous,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              '$count eventos',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (historyItems.isNotEmpty)
          ...historyItems
              .take(12)
              .map((item) => _buildCategorizedHistoryTile(item))
        else
          ...fallbackHistory.take(10).map((inst) => _buildHistoryTile(inst)),
      ],
    );
  }

  Widget _buildCategorizedHistoryTile(DiagnosticHistoryItem item) {
    final inst = item.instruction;
    final (badgeBg, badgeFg) = switch (item.category) {
      DiagnosticHistoryCategory.validInstruction => (
        const Color(0xFF2ECC71).withValues(alpha: 0.18),
        const Color(0xFF2ECC71),
      ),
      DiagnosticHistoryCategory.ignoredNotification => (
        Colors.grey.withValues(alpha: 0.2),
        const Color(0xFFB0BEC5),
      ),
      DiagnosticHistoryCategory.emptyNotification => (
        Colors.orange.withValues(alpha: 0.18),
        const Color(0xFFFFB74D),
      ),
      DiagnosticHistoryCategory.duplicateInstruction => (
        Colors.blueGrey.withValues(alpha: 0.2),
        const Color(0xFF90A4AE),
      ),
      DiagnosticHistoryCategory.sourceSwitched => (
        Colors.purple.withValues(alpha: 0.2),
        const Color(0xFFCE93D8),
      ),
      DiagnosticHistoryCategory.navigationEnded => (
        Colors.red.withValues(alpha: 0.18),
        const Color(0xFFEF5350),
      ),
      DiagnosticHistoryCategory.sourceRecovered => (
        AppColors.cyanLuminous.withValues(alpha: 0.2),
        AppColors.cyanLuminous,
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Row(
        children: [
          Icon(
            _getManeuverIconData(inst.maneuverType),
            color: _getStatusColor(inst.status),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
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
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.category.label,
                        style: TextStyle(
                          color: badgeFg,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        inst.rawText.isNotEmpty
                            ? inst.rawText
                            : (inst.isEmptyNotification
                                  ? '(Notificación sin texto extraíble)'
                                  : inst.maneuverType.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.coldWhite,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${inst.source.displayName} • ${inst.receivedAt.toIso8601String().substring(11, 19)}${item.detail != null ? " • ${item.detail}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          if (inst.distanceMeters != null) ...[
            const SizedBox(width: 8),
            Text(
              '${inst.distanceMeters}m',
              style: const TextStyle(
                color: AppColors.cyanLuminous,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BridgeNavigationInstruction inst) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Row(
        children: [
          Icon(
            _getManeuverIconData(inst.maneuverType),
            color: _getStatusColor(inst.status),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inst.rawText.isNotEmpty
                      ? inst.rawText
                      : (inst.isEmptyNotification
                            ? '(Notificación sin texto extraíble)'
                            : inst.maneuverType.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.coldWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${inst.source.displayName} • ${inst.receivedAt.toIso8601String().substring(11, 19)}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (inst.distanceMeters != null)
            Text(
              '${inst.distanceMeters}m',
              style: const TextStyle(
                color: AppColors.cyanLuminous,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(BridgeSourceType source) {
    Color bg = AppColors.cardNavy;
    Color fg = AppColors.coldWhite;

    if (source == BridgeSourceType.googleMaps) {
      bg = const Color(0xFF1A73E8).withValues(alpha: 0.2);
      fg = const Color(0xFF4285F4);
    } else if (source == BridgeSourceType.waze) {
      bg = const Color(0xFF33CCFF).withValues(alpha: 0.2);
      fg = const Color(0xFF33CCFF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            source.displayName,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BridgeInstructionStatus status) {
    switch (status) {
      case BridgeInstructionStatus.recognized:
        return AppColors.success;
      case BridgeInstructionStatus.incomplete:
        return AppColors.warning;
      case BridgeInstructionStatus.unrecognized:
        return AppColors.inactive;
      case BridgeInstructionStatus.stale:
        return AppColors.error;
    }
  }

  Widget _buildManeuverIcon(ManeuverType type) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.nightBlue,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Icon(
        _getManeuverIconData(type),
        color: AppColors.cyanLuminous,
        size: 26,
      ),
    );
  }

  IconData _getManeuverIconData(ManeuverType type) {
    switch (type) {
      case ManeuverType.straight:
        return Icons.arrow_upward;
      case ManeuverType.left:
        return Icons.turn_left;
      case ManeuverType.slightLeft:
        return Icons.north_west;
      case ManeuverType.sharpLeft:
        return Icons.u_turn_left;
      case ManeuverType.right:
        return Icons.turn_right;
      case ManeuverType.slightRight:
        return Icons.north_east;
      case ManeuverType.sharpRight:
        return Icons.u_turn_right;
      case ManeuverType.uTurn:
        return Icons.u_turn_left;
      case ManeuverType.roundabout:
        return Icons.refresh;
      case ManeuverType.arrive:
        return Icons.sports_score;
      case ManeuverType.depart:
        return Icons.navigation;
      case ManeuverType.unknown:
        return Icons.help_outline;
    }
  }

  String _getManeuverTitle(BridgeNavigationInstruction inst) {
    switch (inst.maneuverType) {
      case ManeuverType.straight:
        return 'Continúa recto';
      case ManeuverType.left:
        return 'Gira a la izquierda';
      case ManeuverType.slightLeft:
        return 'Giro leve a la izquierda';
      case ManeuverType.sharpLeft:
        return 'Giro cerrado a la izquierda';
      case ManeuverType.right:
        return 'Gira a la derecha';
      case ManeuverType.slightRight:
        return 'Giro leve a la derecha';
      case ManeuverType.sharpRight:
        return 'Giro cerrado a la derecha';
      case ManeuverType.uTurn:
        return 'Cambio de sentido en U';
      case ManeuverType.roundabout:
        return 'Entra en la rotonda';
      case ManeuverType.arrive:
        return 'Has llegado a tu destino';
      case ManeuverType.depart:
        return 'Inicia la ruta';
      case ManeuverType.unknown:
        if (inst.isEmptyNotification) {
          return 'Notificación sin texto extraíble';
        }
        if (inst.isIncomplete) {
          return 'Maniobra no identificada';
        }
        return 'Texto no interpretado';
    }
  }
}
