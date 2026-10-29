import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/road_curvature.dart';
import '../../domain/entities/simulated_maneuver_step.dart';
import '../../domain/services/navigation_simulator_service.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../../../domain/entities/maneuver_type.dart';

/// Panel interactivo de control, telemetría y diagnóstico para el Modo de Simulación de Navegación.
///
/// Soporta la ruta Pereira → Santa Rosa de Cabal, análisis de curvas de calzada,
/// semáforo de proximidad reactivo (Verde / Amarillo / Rojo), modo de aproximación rápida
/// y sincronización protegida con el Royal Enfield Tripper Pod por Bluetooth LE.
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
        final isBleReady =
            bleService?.currentState.isReadyForNavigation ?? false;

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
              color:
                  isRunning
                      ? Colors.greenAccent.withValues(alpha: 0.5)
                      : AppColors.cardBorder,
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Encabezado y Estado de Simulación
              Row(
                children: [
                  const Icon(
                    Icons.route_rounded,
                    color: AppColors.primaryGold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modo Simulación de Navegación',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          simulator.routeName,
                          style: const TextStyle(
                            color: AppColors.primaryGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
              const SizedBox(height: 10),

              // 2. Banner descriptivo de aislamiento GPS
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
                        'Simulación con reloj virtual y geometría vial real (Pereira → Santa Rosa). No modifica el sensor GPS.',
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

              // 3. SEMÁFORO GRANDE DE PROXIMIDAD (Verde / Amarillo / Rojo)
              _buildProximityTrafficLightCard(),
              const SizedBox(height: 12),

              // 4. TARJETA DE CURVA DE CARRETERA Y MANIOBRA ACTIVA
              _buildCurvatureAndManeuverCard(step),
              const SizedBox(height: 12),

              // 5. BOTÓN DE MODO DE PRUEBA RÁPIDA DE APROXIMACIÓN A CURVA
              _buildQuickApproachTestButton(),
              const SizedBox(height: 12),

              // 6. Barra de progreso y métricas de avance
              _buildProgressSection(),
              const SizedBox(height: 12),

              // 7. Selector de velocidad virtual (10, 30, 60 km/h)
              _buildSpeedSelector(),
              const SizedBox(height: 12),

              // 8. Controles de transporte (Iniciar, Pausar, Reanudar, Reset, Paso manual)
              _buildControlsBar(isRunning, isPaused),
              const SizedBox(height: 12),

              // 9. Conmutador de transmisión física BLE
              _buildBleTransmissionSwitch(isBleReady),
              const SizedBox(height: 12),

              // 10. Panel de telemetría y diagnóstico detallado
              _buildDiagnosticsTelemetryCard(),
            ],
          ),
        );
      },
    );
  }

  /// Tarjeta del Semáforo Grande de Proximidad (Verde, Amarillo, Rojo).
  Widget _buildProximityTrafficLightCard() {
    final trafficLight = simulator.trafficLight;
    final distMeters = simulator.currentVirtualDistanceMeters.toInt();

    final isGreen = trafficLight == ProximityTrafficLight.green;
    final isYellow = trafficLight == ProximityTrafficLight.yellow;
    final isRed = trafficLight == ProximityTrafficLight.red;

    Color activeColor;
    String statusDesc;
    if (isRed) {
      activeColor = AppColors.error;
      statusDesc = 'ROJO: MANIOBRA INMINENTE (≤ 50 m)';
    } else if (isYellow) {
      activeColor = Colors.amber;
      statusDesc = 'AMARILLO: EN APROXIMACIÓN (≤ 200 m)';
    } else {
      activeColor = AppColors.success;
      statusDesc = 'VERDE: MANIOBRA LEJANA (> 200 m)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activeColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Semáforo visual con tres lentes circulares
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTrafficLightLens(
                      color: AppColors.error,
                      isActive: isRed,
                      tooltip: 'Rojo (≤ 50 m)',
                    ),
                    const SizedBox(width: 5),
                    _buildTrafficLightLens(
                      color: Colors.amber,
                      isActive: isYellow,
                      tooltip: 'Amarillo (≤ 200 m)',
                    ),
                    const SizedBox(width: 5),
                    _buildTrafficLightLens(
                      color: AppColors.success,
                      isActive: isGreen,
                      tooltip: 'Verde (> 200 m)',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusDesc,
                      style: TextStyle(
                        color: activeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$distMeters metros restantes',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLightLens({
    required Color color,
    required bool isActive,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? color : color.withValues(alpha: 0.18),
          boxShadow:
              isActive
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1.5,
                    ),
                  ]
                  : null,
          border: Border.all(
            color: isActive ? Colors.white : Colors.white12,
            width: isActive ? 1.2 : 0.8,
          ),
        ),
      ),
    );
  }

  /// Tarjeta de Curva de Carretera y Maniobra Activa.
  Widget _buildCurvatureAndManeuverCard(SimulatedManeuverStep step) {
    final curvature = simulator.currentCurvature;
    final isSupported = step.isSupportedByTripper;
    final deltaDeg = curvature.bearingDeltaDegrees;
    final deltaSign = deltaDeg > 0 ? '+${deltaDeg.toStringAsFixed(1)}°' : '${deltaDeg.toStringAsFixed(1)}°';

    IconData maneuverIcon;
    switch (step.maneuver.type) {
      case ManeuverType.straight:
        maneuverIcon = Icons.straight_rounded;
        break;
      case ManeuverType.right:
      case ManeuverType.sharpRight:
      case ManeuverType.slightRight:
        maneuverIcon = Icons.turn_right_rounded;
        break;
      case ManeuverType.left:
      case ManeuverType.sharpLeft:
      case ManeuverType.slightLeft:
        maneuverIcon = Icons.turn_left_rounded;
        break;
      case ManeuverType.arrive:
        maneuverIcon = Icons.flag_rounded;
        break;
      case ManeuverType.depart:
        maneuverIcon = Icons.trip_origin_rounded;
        break;
      case ManeuverType.uTurn:
        maneuverIcon = Icons.u_turn_left_rounded;
        break;
      case ManeuverType.roundabout:
        maneuverIcon = Icons.roundabout_left_rounded;
        break;
      case ManeuverType.unknown:
        maneuverIcon = Icons.help_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isSupported
                  ? AppColors.primaryGold.withValues(alpha: 0.3)
                  : Colors.orangeAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Maniobra próxima
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      isSupported
                          ? AppColors.primaryGold.withValues(alpha: 0.15)
                          : Colors.orangeAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  maneuverIcon,
                  color:
                      isSupported
                          ? AppColors.primaryGold
                          : Colors.orangeAccent,
                  size: 22,
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
                            color:
                                isSupported
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isSupported
                                ? 'TRIPPER CMD 0x${step.tripperManeuverCode?.toRadixString(16).toUpperCase().padLeft(2, "0")}'
                                : 'SÓLO LOCAL',
                            style: TextStyle(
                              color:
                                  isSupported
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Curvatura de Carretera Estimada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Icon(
                  curvature.type.icon,
                  color: curvature.type.isCurve ? AppColors.secondaryCyan : AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Curva estimada: ${curvature.type.displayName}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        curvature.type == RoadCurvatureType.straight
                            ? 'Variación de rumbo despreciable (< 10°)'
                            : 'Delta de rumbo: $deltaSign a ${curvature.distanceToCurveMeters.toInt()}m',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.compatibilityNote,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Botón interactivo de prueba rápida de aproximación (300 m → 0 m).
  Widget _buildQuickApproachTestButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryGold,
          side: const BorderSide(color: AppColors.primaryGold, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.flash_on_rounded, size: 16),
        label: const Text(
          'Probar aproximación rápida a curva (300 m → 0 m)',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
        ),
        onPressed: simulator.approachQuickCurveTest,
      ),
    );
  }

  Widget _buildProgressSection() {
    final progress = simulator.progressPercentage;
    final remainingM = simulator.totalRemainingDistanceMeters.toInt();
    final traveledM = simulator.traveledDistanceMeters.toInt();

    final remainingStr =
        remainingM >= 1000
            ? '${(remainingM / 1000.0).toStringAsFixed(1)} km'
            : '$remainingM m';
    final traveledStr =
        traveledM >= 1000
            ? '${(traveledM / 1000.0).toStringAsFixed(1)} km'
            : '$traveledM m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recorrido: $traveledStr (${progress.toStringAsFixed(1)}%)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Restante: $remainingStr',
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
          'Velocidad virtual:',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Wrap(
          spacing: 6,
          children:
              SimulationSpeed.values.map((spd) {
                final isSelected = simulator.speed == spd;
                return ChoiceChip(
                  label: Text(
                    spd.displayName,
                    style: TextStyle(
                      color: isSelected ? Colors.black : AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primaryGold,
                  backgroundColor: Colors.white10,
                  onSelected: (_) => simulator.setSpeed(spd),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildControlsBar(bool isRunning, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Reiniciar desde el inicio',
          icon: const Icon(Icons.replay_rounded),
          color: AppColors.textPrimary,
          onPressed: simulator.reset,
        ),
        IconButton(
          tooltip: 'Maniobra anterior',
          icon: const Icon(Icons.skip_previous_rounded),
          color:
              simulator.currentStepIndex > 0
                  ? AppColors.textPrimary
                  : Colors.white24,
          onPressed:
              simulator.currentStepIndex > 0 ? simulator.stepPrevious : null,
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isRunning ? Colors.orangeAccent : AppColors.primaryGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(
            isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(
            isRunning ? 'Pausar' : (isPaused ? 'Reanudar' : 'Iniciar'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: simulator.togglePlayPause,
        ),
        IconButton(
          tooltip: 'Siguiente maniobra',
          icon: const Icon(Icons.skip_next_rounded),
          color:
              simulator.currentStepIndex < simulator.totalSteps - 1
                  ? AppColors.textPrimary
                  : Colors.white24,
          onPressed:
              simulator.currentStepIndex < simulator.totalSteps - 1
                  ? simulator.stepNext
                  : null,
        ),
        IconButton(
          tooltip: 'Detener simulación',
          icon: const Icon(Icons.stop_rounded),
          color: Colors.redAccent,
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
                      ? 'Conectado a RE_DISP. Solo maniobras con opcode validado se transmitirán.'
                      : 'Tripper Pod no listo. La simulación avanzará localmente.',
                  style: TextStyle(
                    color:
                        isBleReady
                            ? Colors.greenAccent
                            : AppColors.textSecondary,
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
    final lastRes =
        simulator.lastTransmissionResult ?? 'En espera de ejecución';
    final timeStr =
        simulator.lastTransmissionTime != null
            ? simulator.lastTransmissionTime!.toIso8601String().substring(11, 19)
            : 'N/A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIAGNÓSTICO Y TELEMETRÍA EN VIVO',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          _buildTelemetryRow(
            'Dispositivo BLE:',
            dev != null ? '${dev.name} (${dev.id})' : 'Desconectado',
            dev != null ? Colors.greenAccent : AppColors.textSecondary,
          ),
          _buildTelemetryRow('Instrucción simulada:', lastInst, AppColors.textPrimary),
          _buildTelemetryRow('Última trama HEX:', lastHex, AppColors.secondaryCyan),
          _buildTelemetryRow('Hora envío:', timeStr, AppColors.textSecondary),
          _buildTelemetryRow('Resultado GATT:', lastRes, Colors.white70),
          _buildTelemetryRow(
            'Instrucciones generadas / enviadas:',
            '${simulator.generatedInstructionsCount} gen / ${simulator.transmittedInstructionsCount} env',
            AppColors.primaryGold,
          ),
          _buildTelemetryRow(
            'Metraje activo en Pod:',
            simulator.lastBleTransmittedDistance != null
                ? '${simulator.lastBleTransmittedDistance} m'
                : 'Ninguno (Omitido o reposo)',
            simulator.lastBleTransmittedDistance != null
                ? Colors.greenAccent
                : AppColors.textSecondary,
          ),
          if (simulator.lastTraceEvent != null) ...[
            _buildTelemetryRow(
              'Acción trazabilidad:',
              simulator.lastTraceEvent!.action.label,
              simulator.lastTraceEvent!.action.label == 'TRANSMITIDA'
                  ? Colors.greenAccent
                  : Colors.amberAccent,
            ),
            _buildTelemetryRow(
              'Motivo / Justificación:',
              simulator.lastTraceEvent!.reason,
              AppColors.textSecondary,
            ),
          ],
          const Divider(color: Colors.white12, height: 16),
          const Text(
            'Nota técnica: "Escritura GATT OK" certifica la entrega del paquete al buffer BLE de Android. '
            'Las curvas no validadas en hardware se simulan localmente para evitar corromper la pantalla del Pod.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 10.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
