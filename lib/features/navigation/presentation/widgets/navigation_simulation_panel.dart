import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/simulated_maneuver_step.dart';
import '../../domain/services/navigation_simulator_service.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../../../domain/entities/maneuver_type.dart';

/// Panel interactivo de control y diagnóstico para el Modo de Simulación de Navegación.
///
/// Permite reproducir escenarios deterministas de maniobras viales, ajustar
/// velocidad (10, 30, 60 km/h), avanzar manualmente y sincronizar tramas
/// físicas con el Royal Enfield Tripper Pod por Bluetooth LE.
class NavigationSimulationPanel extends StatelessWidget {
  final NavigationSimulatorService simulator;
  final TripperBleService? bleService;

  const NavigationSimulationPanel({
    super.key,
    required this.simulator,
    this.bleService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simulator,
      builder: (context, _) {
        final step = simulator.currentStep;
        final status = simulator.status;
        final isRunning = simulator.isRunning;
        final isPaused = simulator.isPaused;
        final isBleReady = bleService?.currentState.isReadyForNavigation ?? false;

        Color statusColor;
        switch (status) {
          case SimulationStatus.running:
            statusColor = Colors.greenAccent;
            break;
          case SimulationStatus.paused:
            statusColor = Colors.orangeAccent;
            break;
          case SimulationStatus.completed:
            statusColor = AppColors.secondaryCyan;
            break;
          case SimulationStatus.stopped:
            statusColor = AppColors.textSecondary;
            break;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.backgroundCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRunning
                  ? Colors.greenAccent.withValues(alpha: 0.5)
                  : AppColors.cardBorder,
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  const Icon(
                    Icons.route_rounded,
                    color: AppColors.primaryGold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Modo Simulación de Navegación',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      status.displayName.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Banner descriptivo de aislamiento GPS
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey.shade700),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.satellite_alt_rounded,
                      color: AppColors.secondaryCyan,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Simulación con reloj virtual independiente del GPS real. No modifica coordenadas del sensor.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Tarjeta de la maniobra activa
              _buildActiveManeuverCard(step),
              const SizedBox(height: 12),

              // Barra de progreso y métricas virtuales
              _buildProgressSection(),
              const SizedBox(height: 12),

              // Selector de velocidad virtual
              _buildSpeedSelector(),
              const SizedBox(height: 12),

              // Controles de transporte (Play, Pausa, Adelante, Atrás, Reset, Stop)
              _buildControlsBar(isRunning, isPaused),
              const SizedBox(height: 12),

              // Conmutador de transmisión física BLE
              _buildBleTransmissionSwitch(isBleReady),
              const SizedBox(height: 12),

              // Panel de telemetría y diagnóstico detallado
              _buildDiagnosticsTelemetryCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveManeuverCard(SimulatedManeuverStep step) {
    IconData icon;
    switch (step.maneuver.type) {
      case ManeuverType.straight:
        icon = Icons.straight_rounded;
        break;
      case ManeuverType.right:
      case ManeuverType.sharpRight:
      case ManeuverType.slightRight:
        icon = Icons.turn_right_rounded;
        break;
      case ManeuverType.left:
      case ManeuverType.sharpLeft:
      case ManeuverType.slightLeft:
        icon = Icons.turn_left_rounded;
        break;
      case ManeuverType.arrive:
        icon = Icons.flag_rounded;
        break;
      case ManeuverType.depart:
        icon = Icons.trip_origin_rounded;
        break;
      case ManeuverType.uTurn:
        icon = Icons.u_turn_left_rounded;
        break;
      case ManeuverType.roundabout:
        icon = Icons.roundabout_left_rounded;
        break;
      case ManeuverType.unknown:
        icon = Icons.help_outline_rounded;
        break;
    }

    final distanceMeters = simulator.currentVirtualDistanceMeters.toInt();
    final isSupported = step.isSupportedByTripper;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSupported
              ? AppColors.primaryGold.withValues(alpha: 0.3)
              : Colors.orangeAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSupported
                      ? AppColors.primaryGold.withValues(alpha: 0.15)
                      : Colors.orangeAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSupported
                      ? AppColors.primaryGold
                      : Colors.orangeAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Paso ${step.stepNumber} de ${simulator.totalSteps}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSupported
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isSupported
                                ? 'TRIPPER CMD 0x${step.tripperManeuverCode?.toRadixString(16).toUpperCase().padLeft(2, "0")}'
                                : 'SÓLO LOCAL',
                            style: TextStyle(
                              color: isSupported
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.maneuver.instructionText,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniMetric(
                label: 'Distancia virtual',
                value: '$distanceMeters m',
                icon: Icons.straighten_rounded,
              ),
              const SizedBox(width: 12),
              _buildMiniMetric(
                label: 'Vía',
                value: step.maneuver.roadName ?? 'Ruta general',
                icon: Icons.alt_route_rounded,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            step.compatibilityNote,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final progress = simulator.progressPercentage;
    final remainingM = simulator.totalRemainingDistanceMeters.toInt();
    final remainingStr = remainingM >= 1000
        ? '${(remainingM / 1000.0).toStringAsFixed(1)} km'
        : '$remainingM m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progreso: ${progress.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Distancia restante: $remainingStr',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (progress / 100.0).clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.primaryGold,
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedSelector() {
    return Row(
      children: [
        const Text(
          'Velocidad:',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: SimulationSpeed.values.map((s) {
              final isSelected = simulator.speed == s;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => simulator.setSpeed(s),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryGold
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.displayName,
                        style: TextStyle(
                          color: isSelected ? Colors.black : AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsBar(bool isRunning, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reiniciar
        IconButton(
          tooltip: 'Reiniciar desde el inicio',
          icon: const Icon(Icons.replay_rounded),
          color: AppColors.textPrimary,
          onPressed: simulator.reset,
        ),

        // Paso anterior
        IconButton(
          tooltip: 'Maniobra anterior',
          icon: const Icon(Icons.skip_previous_rounded),
          color: simulator.currentStepIndex > 0
              ? AppColors.textPrimary
              : Colors.white24,
          onPressed: simulator.currentStepIndex > 0
              ? simulator.stepPrevious
              : null,
        ),

        // Botón principal (Iniciar / Pausar / Reanudar)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isRunning
                ? Colors.orangeAccent
                : AppColors.primaryGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(
            isRunning
                ? Icons.pause_rounded
                : (isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.play_arrow_rounded),
            size: 20,
          ),
          label: Text(
            isRunning
                ? 'Pausar'
                : (isPaused ? 'Reanudar' : 'Iniciar Simulación'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          onPressed: simulator.togglePlayPause,
        ),

        // Paso siguiente (Avance manual)
        IconButton(
          tooltip: 'Avanzar a la siguiente maniobra',
          icon: const Icon(Icons.skip_next_rounded),
          color: simulator.currentStepIndex < simulator.totalSteps - 1
              ? AppColors.primaryGold
              : Colors.white24,
          onPressed: simulator.currentStepIndex < simulator.totalSteps - 1
              ? simulator.stepNext
              : null,
        ),

        // Detener / Finalizar
        IconButton(
          tooltip: 'Finalizar simulación',
          icon: const Icon(Icons.stop_rounded),
          color: isRunning || isPaused ? Colors.redAccent : Colors.white24,
          onPressed: isRunning || isPaused ? simulator.stop : null,
        ),
      ],
    );
  }

  Widget _buildBleTransmissionSwitch(bool isBleReady) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Transmitir al Tripper Pod físico (BLE)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isBleReady
                      ? 'Conectado a RE_DISP. Las maniobras compatibles se emitirán por BLE.'
                      : 'Tripper Pod no listo. La simulación avanzará localmente.',
                  style: TextStyle(
                    color: isBleReady ? Colors.greenAccent : AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: simulator.transmitToBle,
            activeThumbColor: AppColors.primaryGold,
            onChanged: (val) => simulator.setTransmitToBle(val),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsTelemetryCard() {
    final dev = bleService?.connectedDevice;
    final lastHex = simulator.lastTransmittedHex ?? 'Ninguna trama enviada aún';
    final lastInst = simulator.lastSimulatedInstruction ?? 'Sin instrucciones';
    final lastRes = simulator.lastTransmissionResult ?? 'En espera de ejecución';
    final timeStr = simulator.lastTransmissionTime != null
        ? simulator.lastTransmissionTime!.toIso8601String().substring(11, 19)
        : 'N/A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: AppColors.secondaryCyan, size: 16),
              SizedBox(width: 6),
              Text(
                'Diagnóstico de Simulación & Enlace',
                style: TextStyle(
                  color: AppColors.secondaryCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTelemetryLine('Dispositivo:', dev != null ? '${dev.name} (${dev.id})' : 'Sin conexión BLE'),
          _buildTelemetryLine('Última instrucción:', lastInst),
          _buildTelemetryLine('Última trama enviada:', lastHex, isCode: true),
          _buildTelemetryLine('Hora último envío:', timeStr),
          _buildTelemetryLine('Resultado escritura:', lastRes),
          _buildTelemetryLine(
            'Contador instrucciones:',
            'Generadas: ${simulator.generatedInstructionsCount} | Emitidas al Pod: ${simulator.transmittedInstructionsCount}',
          ),
          const SizedBox(height: 6),
          const Text(
            'AVISO: "OK" confirma aceptación en bus GATT de Android. La confirmación visual requiere verificación en el display físico del Tripper Pod.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9.5,
              fontStyle: FontStyle.italic,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryLine(String label, String value, {bool isCode = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isCode ? AppColors.primaryGold : AppColors.textPrimary,
                fontSize: 10.5,
                fontFamily: isCode ? 'monospace' : null,
                fontWeight: isCode ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 14),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
