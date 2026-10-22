import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../domain/entities/bridge_instruction_status.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../infrastructure/services/bridge_native_channel.dart';
import '../state/bridge_diagnostic_controller.dart';

/// Pantalla de diagnóstico técnico para la captura de notificaciones de ESTELA Bridge.
///
/// Permite al motociclista verificar en tiempo real:
/// 1. El estado del permiso del sistema Android (Notification Listener).
/// 2. La interceptación de eventos de Google Maps y Waze.
/// 3. La extracción de maniobras, distancias y calles por el parser.
/// 4. La clasificación rigurosa del estado de la instrucción.
class BridgeDiagnosticScreen extends StatefulWidget {
  final BridgeDiagnosticController? controller;

  const BridgeDiagnosticScreen({super.key, this.controller});

  @override
  State<BridgeDiagnosticScreen> createState() => _BridgeDiagnosticScreenState();
}

class _BridgeDiagnosticScreenState extends State<BridgeDiagnosticScreen> {
  late final BridgeDiagnosticController _controller;
  bool _isInternalController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = BridgeDiagnosticController();
      _isInternalController = true;
    }
    _controller.initialize();
  }

  @override
  void dispose() {
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
                tooltip: 'Actualizar permiso',
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
              _buildHistorySection(),
            ],
          ),
        );
      },
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
              const Text(
                'Filtro: Maps | Waze',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11,
                  fontFamily: 'monospace',
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
                      : '(Sin texto disponible)',
                  style: const TextStyle(
                    color: AppColors.coldWhite,
                    fontSize: 12,
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

  Widget _buildHistorySection() {
    final history = _controller.sessionHistory;
    if (history.isEmpty) return const SizedBox.shrink();

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
              '${history.length} eventos',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.take(10).map((inst) => _buildHistoryTile(inst)),
      ],
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
                      : inst.maneuverType.name,
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
        if (inst.isIncomplete) {
          return 'Maniobra no identificada';
        }
        return 'Texto no interpretado';
    }
  }
}
