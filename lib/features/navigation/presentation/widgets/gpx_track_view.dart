import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/imported_gpx_route.dart';

/// Visualizador esquemático y vectorial de un trazado GPX y posición GPS en tiempo real.
///
/// Proyecta los puntos geográficos reales sobre el lienzo del canvas mediante
/// una proyección equirrectangular local centrada, diferenciando cada segmento
/// sin unir tramos discontinuos, y dibujando la posición y rastro del motociclista.
class GpxTrackView extends StatelessWidget {
  final ImportedGpxRoute route;
  final Coordinates? currentRiderPosition;
  final Coordinates? projectedPoint;
  final List<Coordinates>? recentTrail;
  final double height;
  final VoidCallback? onRecenter;

  const GpxTrackView({
    super.key,
    required this.route,
    this.currentRiderPosition,
    this.projectedPoint,
    this.recentTrail,
    this.height = 240.0,
    this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark
              ? AppColors.steelBlue.withValues(alpha: 0.35)
              : AppColors.silver,
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Rejilla y polilínea GPX dibujada con CustomPainter
          Positioned.fill(
            child: CustomPaint(
              painter: _GpxTrackPainter(
                route: route,
                riderPosition: currentRiderPosition,
                projectedPoint: projectedPoint,
                recentTrail: recentTrail,
                isDark: isDark,
              ),
            ),
          ),

          // 2. Rótulo superior informativo
          Positioned(
            top: 10.0,
            left: 12.0,
            right: 12.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.stormNavy.withValues(alpha: 0.85)
                        : AppColors.lightBackground.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: isDark
                          ? AppColors.steelBlue.withValues(alpha: 0.5)
                          : AppColors.silver,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timeline,
                        size: 14.0,
                        color: isDark
                            ? AppColors.accentBlue
                            : AppColors.steelBlue,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        currentRiderPosition != null
                            ? 'Seguimiento GPS en vivo • Trazado real'
                            : 'Trazado GPX • Puntos reales sin mapa base',
                        style: TextStyle(
                          fontSize: 10.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: isDark
                              ? AppColors.primaryTextDark
                              : AppColors.primaryTextLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.silver.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    '${route.totalPoints} pts',
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Botón de recentrar (si el GPS está activo)
          if (currentRiderPosition != null && onRecenter != null)
            Positioned(
              right: 10.0,
              bottom: 36.0,
              child: Material(
                color: isDark ? AppColors.stormNavy : AppColors.whiteSurface,
                shape: const CircleBorder(),
                elevation: 3.0,
                child: IconButton(
                  icon: const Icon(Icons.my_location, size: 18.0),
                  tooltip: 'Centrar en el trazado',
                  color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                  onPressed: onRecenter,
                ),
              ),
            ),

          // 4. Leyenda inferior de inicio, destino y posición
          Positioned(
            bottom: 8.0,
            left: 12.0,
            right: 12.0,
            child: Row(
              children: [
                _buildLegendItem(
                  color: const Color(0xFF2E7D32),
                  label: 'Inicio',
                  isDark: isDark,
                ),
                const SizedBox(width: 10.0),
                _buildLegendItem(
                  color: const Color(0xFFC62828),
                  label: 'Destino',
                  isDark: isDark,
                ),
                if (currentRiderPosition != null) ...[
                  const SizedBox(width: 10.0),
                  _buildLegendItem(
                    color: const Color(0xFF00E5FF),
                    label: 'Tú',
                    isDark: isDark,
                  ),
                ],
                const Spacer(),
                if (route.segments.length > 1)
                  Text(
                    '${route.segments.length} tramos',
                    style: TextStyle(
                      fontSize: 10.0,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.0,
          height: 8.0,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4.0),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.0,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.secondaryTextDark
                : AppColors.secondaryTextLight,
          ),
        ),
      ],
    );
  }
}

class _GpxTrackPainter extends CustomPainter {
  final ImportedGpxRoute route;
  final Coordinates? riderPosition;
  final Coordinates? projectedPoint;
  final List<Coordinates>? recentTrail;
  final bool isDark;

  _GpxTrackPainter({
    required this.route,
    this.riderPosition,
    this.projectedPoint,
    this.recentTrail,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allCoords = route.allCoordinates;
    if (allCoords.isEmpty) return;

    // 1. Dibujar cuadrícula sutil
    _drawGrid(canvas, size);

    // 2. Calcular límites geográficos envolventes (incluyendo la posición del motociclista)
    double minLat = allCoords.first.latitude;
    double maxLat = allCoords.first.latitude;
    double minLon = allCoords.first.longitude;
    double maxLon = allCoords.first.longitude;

    for (final c in allCoords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    if (riderPosition != null) {
      if (riderPosition!.latitude < minLat) minLat = riderPosition!.latitude;
      if (riderPosition!.latitude > maxLat) maxLat = riderPosition!.latitude;
      if (riderPosition!.longitude < minLon) minLon = riderPosition!.longitude;
      if (riderPosition!.longitude > maxLon) maxLon = riderPosition!.longitude;
    }

    final double latSpan = maxLat - minLat;
    final double lonSpan = maxLon - minLon;
    final double midLatRad = ((minLat + maxLat) / 2.0) * (pi / 180.0);
    final double cosMidLat = cos(midLatRad).abs();

    const double padding = 34.0;
    final double availWidth = size.width - (padding * 2);
    final double availHeight = size.height - (padding * 2);

    if (availWidth <= 0 || availHeight <= 0) return;

    final double scaledLonSpan = (lonSpan == 0 ? 0.0001 : lonSpan) * cosMidLat;
    final double effectiveLatSpan = latSpan == 0 ? 0.0001 : latSpan;

    final double scaleX = availWidth / scaledLonSpan;
    final double scaleY = availHeight / effectiveLatSpan;
    final double scale = min(scaleX, scaleY);

    final double contentWidth = scaledLonSpan * scale;
    final double contentHeight = effectiveLatSpan * scale;
    final double offsetX = padding + (availWidth - contentWidth) / 2.0;
    final double offsetY = padding + (availHeight - contentHeight) / 2.0;

    Offset project(double lat, double lon) {
      final double x = offsetX + ((lon - minLon) * cosMidLat * scale);
      final double y = offsetY + ((maxLat - lat) * scale);
      return Offset(x, y);
    }

    // 3. Dibujar cada segmento de la ruta de manera independiente
    final linePaint = Paint()
      ..color = isDark ? AppColors.accentBlue : AppColors.steelBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shadowPaint = Paint()
      ..color = (isDark ? AppColors.accentBlue : AppColors.steelBlue)
          .withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final segment in route.segments) {
      if (segment.points.isEmpty) continue;

      if (segment.points.length == 1) {
        final pt = project(
          segment.points.first.latitude,
          segment.points.first.longitude,
        );
        canvas.drawCircle(pt, 4.0, linePaint..style = PaintingStyle.fill);
        continue;
      }

      final path = Path();
      final firstPt = project(
        segment.points.first.latitude,
        segment.points.first.longitude,
      );
      path.moveTo(firstPt.dx, firstPt.dy);

      for (int i = 1; i < segment.points.length; i++) {
        final pt = project(
          segment.points[i].latitude,
          segment.points[i].longitude,
        );
        path.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, linePaint);
    }

    // 4. Dibujar rastro reciente del motociclista (si existe)
    if (recentTrail != null && recentTrail!.length > 1) {
      final trailPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final trailPath = Path();
      final startPt = project(
        recentTrail!.first.latitude,
        recentTrail!.first.longitude,
      );
      trailPath.moveTo(startPt.dx, startPt.dy);
      for (int i = 1; i < recentTrail!.length; i++) {
        final pt = project(recentTrail![i].latitude, recentTrail![i].longitude);
        trailPath.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(trailPath, trailPaint);
    }

    // 5. Dibujar línea ortogonal hacia el punto proyectado si hay desvío
    if (riderPosition != null && projectedPoint != null) {
      final riderOffset = project(
        riderPosition!.latitude,
        riderPosition!.longitude,
      );
      final projOffset = project(
        projectedPoint!.latitude,
        projectedPoint!.longitude,
      );

      final connectionPaint = Paint()
        ..color = Colors.amber.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(riderOffset, projOffset, connectionPaint);
      canvas.drawCircle(projOffset, 3.0, Paint()..color = Colors.amber);
    }

    // 6. Marcador de Inicio
    final firstSeg = route.segments.firstWhere(
      (s) => s.isNotEmpty,
      orElse: () => route.segments.first,
    );
    if (firstSeg.isNotEmpty) {
      final startOffset = project(
        firstSeg.points.first.latitude,
        firstSeg.points.first.longitude,
      );
      _drawMarker(
        canvas: canvas,
        position: startOffset,
        fillColor: const Color(0xFF2E7D32),
        borderColor: Colors.white,
      );
    }

    // 7. Marcador de Destino
    final lastSeg = route.segments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => route.segments.last,
    );
    if (lastSeg.isNotEmpty) {
      final endOffset = project(
        lastSeg.points.last.latitude,
        lastSeg.points.last.longitude,
      );
      _drawMarker(
        canvas: canvas,
        position: endOffset,
        fillColor: const Color(0xFFC62828),
        borderColor: Colors.white,
      );
    }

    // 8. Marcador de Posición del Motociclista (Tú)
    if (riderPosition != null) {
      final riderOffset = project(
        riderPosition!.latitude,
        riderPosition!.longitude,
      );

      // Anillo exterior celeste
      canvas.drawCircle(
        riderOffset,
        10.0,
        Paint()
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.3)
          ..style = PaintingStyle.fill,
      );

      // Borde blanco
      canvas.drawCircle(
        riderOffset,
        6.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      // Centro cian/azul de alta visibilidad
      canvas.drawCircle(
        riderOffset,
        4.5,
        Paint()
          ..color = const Color(0xFF00B0FF)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : AppColors.stormNavy).withValues(
        alpha: 0.04,
      )
      ..strokeWidth = 1.0;

    const double step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawMarker({
    required Canvas canvas,
    required Offset position,
    required Color fillColor,
    required Color borderColor,
  }) {
    canvas.drawCircle(
      position,
      8.0,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    canvas.drawCircle(
      position,
      6.0,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      position,
      4.0,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _GpxTrackPainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.riderPosition != riderPosition ||
        oldDelegate.projectedPoint != projectedPoint ||
        oldDelegate.recentTrail != recentTrail ||
        oldDelegate.isDark != isDark;
  }
}
