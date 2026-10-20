import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/coordinates.dart';

/// Vista esquemática simple de la geometría de calzada.
///
/// Ilustra el trazado y la posición relativa de avance sin fingir que es un mapa GPS real.
class SchematicRoadView extends StatelessWidget {
  final List<Coordinates> geometry;
  final double progressFraction;

  const SchematicRoadView({
    super.key,
    required this.geometry,
    required this.progressFraction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 180.0,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : const Color(0xFFE9F0F6),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark ? const Color(0xFF263A48) : const Color(0xFFD7DFE8),
          width: 1.0,
        ),
      ),
      child: Stack(
        children: [
          // Trazado esquemático dibujado con CustomPaint
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: CustomPaint(
                painter: _SchematicPainter(
                  geometry: geometry,
                  progressFraction: progressFraction,
                  isDark: isDark,
                  accentColor: isDark
                      ? AppColors.accentBlue
                      : AppColors.deepBlue,
                  trackColor: isDark
                      ? const Color(0xFF243B4E)
                      : const Color(0xFFC5D5E4),
                ),
              ),
            ),
          ),

          // Leyenda honesta en la esquina inferior
          Positioned(
            left: 12.0,
            bottom: 8.0,
            right: 12.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 13.0,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      'Esquema de calzada • No es mapa GPS real',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${(progressFraction * 100).toStringAsFixed(0)} %',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.accentBlue : AppColors.deepBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SchematicPainter extends CustomPainter {
  final List<Coordinates> geometry;
  final double progressFraction;
  final bool isDark;
  final Color accentColor;
  final Color trackColor;

  _SchematicPainter({
    required this.geometry,
    required this.progressFraction,
    required this.isDark,
    required this.accentColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.isEmpty) return;

    final w = size.width;
    final h = size.height - 16.0;

    // Normalizar coordenadas a coordenadas relativas del canvas
    double minLat = geometry.first.latitude;
    double maxLat = geometry.first.latitude;
    double minLon = geometry.first.longitude;
    double maxLon = geometry.first.longitude;

    for (final c in geometry) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    final latRange = (maxLat - minLat).abs() > 0 ? (maxLat - minLat) : 1.0;
    final lonRange = (maxLon - minLon).abs() > 0 ? (maxLon - minLon) : 1.0;

    Offset mapPoint(Coordinates c) {
      // Longitud -> X, Latitud invertida -> Y
      final normX = (c.longitude - minLon) / lonRange;
      final normY = 1.0 - ((c.latitude - minLat) / latRange);
      return Offset(normX * (w - 20) + 10, normY * (h - 20) + 10);
    }

    final points = geometry.map(mapPoint).toList();

    // 1. Dibuja la ruta base (pista completa)
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, trackPaint);

    // 2. Dibuja el tramo recorrido con acento activo
    final completedPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double totalSegs = (points.length - 1).toDouble();
    final double exactIndex = progressFraction.clamp(0.0, 1.0) * totalSegs;
    final int curSeg = exactIndex.floor().clamp(0, points.length - 2);
    final double t = exactIndex - curSeg;

    final completedPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i <= curSeg; i++) {
      completedPath.lineTo(points[i].dx, points[i].dy);
    }

    // Punto exacto actual interpolado
    final pA = points[curSeg];
    final pB = points[curSeg + 1];
    final curPos = Offset(
      pA.dx + t * (pB.dx - pA.dx),
      pA.dy + t * (pB.dy - pA.dy),
    );
    completedPath.lineTo(curPos.dx, curPos.dy);

    canvas.drawPath(completedPath, completedPaint);

    // 3. Vértices de waypoints (hitos de ruta)
    final waypointPaint = Paint()
      ..color = isDark ? Colors.white70 : AppColors.deepBlue
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 3.5, waypointPaint);
    }

    // 4. Marcador de origen (verde) y destino (rojo)
    final originPaint = Paint()..color = AppColors.success;
    canvas.drawCircle(points.first, 5.5, originPaint);

    final destPaint = Paint()..color = const Color(0xFFE74C3C);
    canvas.drawCircle(points.last, 6.0, destPaint);

    // 5. Marcador de motocicleta en la posición actual
    final bikeGlowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(curPos, 12.0, bikeGlowPaint);

    final bikePaint = Paint()
      ..color = isDark ? Colors.white : AppColors.stormNavy
      ..style = PaintingStyle.fill;
    canvas.drawCircle(curPos, 6.5, bikePaint);

    final bikeCenterPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(curPos, 3.5, bikeCenterPaint);
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter oldDelegate) {
    return oldDelegate.progressFraction != progressFraction ||
        oldDelegate.isDark != isDark;
  }
}
