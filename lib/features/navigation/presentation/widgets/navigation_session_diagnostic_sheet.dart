import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/services/voice_navigation_service.dart';
import '../../domain/services/navigation_maneuver_engine.dart';
import '../state/gpx_route_tracker.dart';

/// Hoja modal de diagnóstico de sesión en tiempo real para GPS y navegación.
///
/// Permite auditar en vivo la telemetría satelital, calidad del servicio en primer plano,
/// cadencia de actualización y generación de instrucciones sin registrar datos personales.
class NavigationSessionDiagnosticSheet extends StatefulWidget {
  final GpxRouteTracker tracker;
  final NavigationManeuverEngine? maneuverEngine;
  final VoiceNavigationService? voiceService;
  final bool isDemo;

  const NavigationSessionDiagnosticSheet({
    super.key,
    required this.tracker,
    this.maneuverEngine,
    this.voiceService,
    this.isDemo = false,
  });

  static Future<void> show(
    BuildContext context, {
    required GpxRouteTracker tracker,
    NavigationManeuverEngine? maneuverEngine,
    VoiceNavigationService? voiceService,
    bool isDemo = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NavigationSessionDiagnosticSheet(
        tracker: tracker,
        maneuverEngine: maneuverEngine,
        voiceService: voiceService,
        isDemo: isDemo,
      ),
    );
  }

  @override
  State<NavigationSessionDiagnosticSheet> createState() =>
      _NavigationSessionDiagnosticSheetState();
}

class _NavigationSessionDiagnosticSheetState
    extends State<NavigationSessionDiagnosticSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresco periódico para actualizar la edad en segundos de la posición
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.tracker.addListener(_onTrackerChange);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.tracker.removeListener(_onTrackerChange);
    super.dispose();
  }

  void _onTrackerChange() {
    if (mounted) setState(() {});
  }

  void _copyDiagnosticsToClipboard() {
    final t = widget.tracker;
    final pos = t.currentPosition;
    final step = widget.maneuverEngine?.lastResolvedStep;

    final buffer = StringBuffer();
    buffer.writeln('=== DIAGNÓSTICO DE SESIÓN GPS — RESTELAR ===');
    buffer.writeln(
      'Modo: ${widget.isDemo ? "DEMO (Simulación)" : "GPS REAL (Sensor físico)"}',
    );
    buffer.writeln('Estado de Navegación: ${t.status.name}');
    buffer.writeln(
      'Servicio Segundo Plano: ${t.isBackgroundEnabled ? "ACTIVO (Foreground Service)" : "INACTIVO"}',
    );
    buffer.writeln('Posiciones recibidas: ${t.totalPositionsReceived}');
    buffer.writeln('Posiciones válidas filtradas: ${t.validSamplesCount}');
    buffer.writeln(
      'Hora última lectura: ${t.lastPositionTime?.toIso8601String() ?? "Sin lecturas"}',
    );
    buffer.writeln('Edad de la posición: ${t.lastPositionAgeSeconds} s');
    if (pos != null) {
      buffer.writeln(
        'Precisión horizontal: ±${pos.accuracyMeters.toStringAsFixed(1)} m',
      );
      buffer.writeln(
        'Velocidad instantánea: ${pos.speedKmh != null ? "${pos.speedKmh!.toStringAsFixed(1)} km/h" : "No disponible"}',
      );
      buffer.writeln(
        'Altitud: ${pos.altitudeMeters != null ? "${pos.altitudeMeters!.toStringAsFixed(1)} m" : "No disponible"}',
      );
    }
    buffer.writeln(
      'Distancia recorrida: ${(t.distanceTraveledMeters / 1000).toStringAsFixed(2)} km',
    );
    buffer.writeln(
      'Progreso ruta: ${t.progressPercentage.toStringAsFixed(1)}%',
    );
    buffer.writeln(
      'Desvío fuera de ruta: ${t.offRouteDistanceMeters.toStringAsFixed(1)} m',
    );
    if (step != null) {
      buffer.writeln(
        'Próxima maniobra: ${step.activeManeuver.instruction} (en ${step.distanceToManeuverMeters.toStringAsFixed(0)} m)',
      );
    }
    buffer.writeln(
      'Última instrucción voz: ${widget.voiceService?.lastSpokenText ?? "Ninguna emitida aún"}',
    );
    buffer.writeln('Último error GPS: ${t.lastGpsError ?? "Ninguno"}');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnóstico de sesión copiado al portapapeles.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracker;
    final pos = t.currentPosition;
    final isStale = t.isPositionStale;
    final step = widget.maneuverEngine?.lastResolvedStep;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de arrastre superior
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Encabezado
              Row(
                children: [
                  const Icon(
                    Icons.monitor_heart_outlined,
                    color: AppColors.secondaryCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Diagnóstico de Sesión GPS en Vivo',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Alerta explícita de posición estancada o pérdida satelital
              if (isStale) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Señal GPS detenida o estancada',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.lastPositionAgeSeconds >= 0
                                  ? 'La última coordenada se recibió hace ${t.lastPositionAgeSeconds} segundos. Verifica visibilidad de cielo o ahorro de batería de Android.'
                                  : 'Esperando primera lectura satelital del sensor...',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Badges de Modo y Servicio
              Row(
                children: [
                  _buildBadge(
                    label: widget.isDemo
                        ? 'MODO DEMO (SIMULACIÓN)'
                        : 'GPS FÍSICO REAL',
                    color: widget.isDemo
                        ? AppColors.primaryGold
                        : Colors.greenAccent,
                    icon: widget.isDemo
                        ? Icons.science_outlined
                        : Icons.gps_fixed_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildBadge(
                    label: t.isBackgroundEnabled
                        ? 'SEGUNDO PLANO ACTIVO'
                        : 'PRIMER PLANO',
                    color: t.isBackgroundEnabled
                        ? AppColors.secondaryCyan
                        : AppColors.textSecondary,
                    icon: t.isBackgroundEnabled
                        ? Icons.notification_important_rounded
                        : Icons.phone_android_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Rejilla de métricas de telemetría GPS
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    _buildMetricRow(
                      'Estado de Navegación',
                      t.status.name.toUpperCase(),
                      highlightColor: t.isTracking
                          ? Colors.greenAccent
                          : AppColors.primaryGold,
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Última posición GPS',
                      t.lastPositionTime != null
                          ? '${t.lastPositionTime!.hour.toString().padLeft(2, '0')}:${t.lastPositionTime!.minute.toString().padLeft(2, '0')}:${t.lastPositionTime!.second.toString().padLeft(2, '0')}'
                          : 'Sin coordenadas',
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Edad de la posición',
                      t.lastPositionAgeSeconds >= 0
                          ? '${t.lastPositionAgeSeconds} seg'
                          : 'N/A',
                      highlightColor: isStale
                          ? Colors.redAccent
                          : Colors.greenAccent,
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Precisión horizontal',
                      pos != null
                          ? '±${pos.accuracyMeters.toStringAsFixed(1)} m'
                          : 'Sin señal',
                      highlightColor: pos != null && pos.accuracyMeters <= 20
                          ? Colors.greenAccent
                          : AppColors.primaryGold,
                    ),
                    if (pos != null) ...[
                      const Divider(color: Colors.white10, height: 14),
                      _buildMetricRow(
                        'Coordenadas actuales',
                        '${pos.coordinates.latitude.toStringAsFixed(6)}, ${pos.coordinates.longitude.toStringAsFixed(6)}',
                      ),
                    ],
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Posiciones recibidas',
                      '${t.totalPositionsReceived} (${t.validSamplesCount} válidas)',
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Tiempo entre actualizaciones',
                      t.lastPositionInterval != null
                          ? '${t.lastPositionInterval!.inMilliseconds} ms'
                          : 'Esperando segundo punto...',
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Distancia recorrida',
                      '${(t.distanceTraveledMeters / 1000).toStringAsFixed(2)} km (${t.progressPercentage.toStringAsFixed(1)}%)',
                    ),
                    if (pos != null) ...[
                      const Divider(color: Colors.white10, height: 14),
                      _buildMetricRow(
                        'Velocidad actual',
                        pos.speedKmh != null
                            ? '${pos.speedKmh!.toStringAsFixed(1)} km/h (Máx: ${(t.maxSpeedKmh ?? 0).toStringAsFixed(1)} km/h)'
                            : '0.0 km/h',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Próxima Maniobra e Instrucción de Voz
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instrucciones de Ruta y Voz',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMetricRow(
                      'Próxima maniobra',
                      step != null
                          ? step.activeManeuver.instruction
                          : 'Calculando paso...',
                    ),
                    const SizedBox(height: 6),
                    _buildMetricRow(
                      'Distancia al giro',
                      step != null
                          ? '${step.distanceToManeuverMeters.toStringAsFixed(0)} metros'
                          : 'N/A',
                      highlightColor: AppColors.primaryGold,
                    ),
                    const Divider(color: Colors.white10, height: 14),
                    _buildMetricRow(
                      'Última locución TTS',
                      widget.voiceService?.lastSpokenText ??
                          'Ninguna instrucción emitida aún',
                      highlightColor: AppColors.secondaryCyan,
                    ),
                    if (t.lastGpsError != null) ...[
                      const Divider(color: Colors.white10, height: 14),
                      _buildMetricRow(
                        'Último error GPS',
                        t.lastGpsError!,
                        highlightColor: Colors.redAccent,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Botón de copia al portapapeles
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text(
                    'Copiar diagnóstico de sesión completo',
                    style: TextStyle(fontSize: 13),
                  ),
                  onPressed: _copyDiagnosticsToClipboard,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {Color? highlightColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: highlightColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}
