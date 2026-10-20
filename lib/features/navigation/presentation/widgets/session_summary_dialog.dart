import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/storm_badge.dart';
import '../../domain/entities/navigation_session.dart';

/// Diálogo modal que presenta el resumen de una sesión de seguimiento finalizada.
class SessionSummaryDialog extends StatelessWidget {
  final NavigationSession session;

  const SessionSummaryDialog({super.key, required this.session});

  static Future<void> show(BuildContext context, NavigationSession session) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SessionSummaryDialog(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            session.isCompleted
                ? Icons.emoji_events_outlined
                : Icons.flag_outlined,
            color: session.isCompleted
                ? const Color(0xFF2E7D32)
                : (isDark ? AppColors.accentBlue : AppColors.steelBlue),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              session.isCompleted ? '¡Ruta completada!' : 'Sesión finalizada',
              style: AppTypography.sectionTitle,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: StormBadge(
                label: session.isCompleted
                    ? 'DESTINO ALCANZADO'
                    : 'INTERRUMPIDA',
                variant: session.isCompleted
                    ? StormBadgeVariant.success
                    : StormBadgeVariant.neutral,
              ),
            ),
            const SizedBox(height: 12.0),
            Text(
              session.routeName,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.primaryTextDark
                    : AppColors.primaryTextLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            const Divider(),
            const SizedBox(height: 8.0),
            _buildRow(
              'Distancia recorrida',
              '${session.distanceTraveledKm.toStringAsFixed(1)} km',
            ),
            _buildRow(
              'Progreso de trazado',
              '${session.progressPercentage.toStringAsFixed(0)} %',
            ),
            _buildRow('Duración activa', _formatDuration(session.duration)),
            if (session.maxSpeedKmh != null)
              _buildRow(
                'Velocidad máxima',
                '${session.maxSpeedKmh!.toStringAsFixed(0)} km/h',
              ),
            _buildRow(
              'Precisión GPS media',
              '±${session.averageAccuracyMeters.toStringAsFixed(1)} m',
            ),
            _buildRow(
              'Muestras satelitales',
              '${session.validGpsSamplesCount} lecturas',
            ),
            const SizedBox(height: 12.0),
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.stormNavy.withValues(alpha: 0.6)
                    : const Color(0xFFF3F6F9),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                'Nota: Métricas calculadas según la geometría GPX y la precisión del GPS móvil.',
                style: TextStyle(
                  fontSize: 10.0,
                  color: isDark
                      ? AppColors.secondaryTextDark
                      : AppColors.secondaryTextLight,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.0)),
          Text(
            value,
            style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h h $m min';
    return '$m min $s s';
  }
}
