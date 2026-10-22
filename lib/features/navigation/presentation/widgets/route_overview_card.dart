import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/calculated_route.dart';
import '../../domain/entities/destination.dart';

/// Tarjeta flotante que presenta el resumen de las rutas disponibles (principal y alternativas)
/// para que el motociclista pueda compararlas, verificar advertencias de seguridad vial
/// y seleccionar la opción deseada antes de iniciar la navegación.
class RouteOverviewCard extends StatelessWidget {
  final Destination destination;
  final List<CalculatedRoute> availableRoutes;
  final int selectedRouteIndex;
  final ValueChanged<int>? onSelectRoute;
  final VoidCallback onStartNavigation;
  final VoidCallback onCancel;
  final VoidCallback? onSaveFavorite;
  final VoidCallback? onReportIssue;

  RouteOverviewCard({
    super.key,
    required this.destination,
    CalculatedRoute? route,
    List<CalculatedRoute>? routes,
    this.selectedRouteIndex = 0,
    this.onSelectRoute,
    required this.onStartNavigation,
    required this.onCancel,
    this.onSaveFavorite,
    this.onReportIssue,
  }) : availableRoutes =
           routes ?? (route != null ? [route] : const <CalculatedRoute>[]);

  CalculatedRoute get selectedRoute {
    if (availableRoutes.isEmpty) {
      throw StateError(
        'RouteOverviewCard requiere al menos una ruta calculada.',
      );
    }
    final index = selectedRouteIndex.clamp(0, availableRoutes.length - 1);
    return availableRoutes[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final current = selectedRoute;
    final validation = current.validation;

    return Container(
      constraints: const BoxConstraints(maxHeight: 520.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Encabezado con destino y botón cancelar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: AppColors.error,
                    size: 20.0,
                  ),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.title,
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        current.summary,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.secondaryText
                              : AppColors.secondaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20.0),
                  onPressed: onCancel,
                  tooltip: 'Cancelar ruta',
                ),
              ],
            ),
            const SizedBox(height: 12.0),

            // 2. Selector de rutas alternativas (si hay más de 1)
            if (availableRoutes.length > 1) ...[
              Text(
                'RUTAS DISPONIBLES (${availableRoutes.length})',
                style: AppTypography.badgeLabel.copyWith(
                  fontSize: 10.0,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6.0),
              SizedBox(
                height: 76.0,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: availableRoutes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8.0),
                  itemBuilder: (context, index) {
                    final r = availableRoutes[index];
                    final isSelected = index == selectedRouteIndex;
                    return _buildRouteSelectorCard(
                      context: context,
                      route: r,
                      index: index,
                      isSelected: isSelected,
                      isDark: isDark,
                      onTap: () => onSelectRoute?.call(index),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12.0),
            ],

            // 3. Métricas principales de la ruta seleccionada
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardNavy : AppColors.lightBackground,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric(
                    label: 'TIEMPO ESTIMADO',
                    value: current.formattedDuration,
                    diffText:
                        current.durationDiff != null &&
                            current.durationDiff!.inMinutes > 0
                        ? '+${current.durationDiff!.inMinutes} min'
                        : (current.isFastest && availableRoutes.length > 1
                              ? 'Más rápida'
                              : null),
                    color: isDark
                        ? AppColors.cyanLuminous
                        : AppColors.surfaceNavy,
                  ),
                  Container(
                    width: 1.0,
                    height: 34.0,
                    color: isDark ? const Color(0xFF264660) : AppColors.silver,
                  ),
                  _buildMetric(
                    label: 'DISTANCIA VIAL',
                    value: '${current.totalDistanceKm.toStringAsFixed(1)} km',
                    diffText:
                        current.distanceDiffKm != null &&
                            current.distanceDiffKm! > 0.05
                        ? '+${current.distanceDiffKm!.toStringAsFixed(1)} km'
                        : (current.isShortest && availableRoutes.length > 1
                              ? 'Más corta'
                              : null),
                    color: isDark
                        ? AppColors.coldWhite
                        : AppColors.primaryTextLight,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10.0),

            // 4. Advertencias de integridad, acceso o transitabilidad
            if (current.isConfirmedRestricted) ...[
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block, color: AppColors.error, size: 18.0),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Acceso restringido / Vía privada con cerrojo',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          for (final w in validation.warnings)
                            Text(
                              '• $w',
                              style: TextStyle(
                                fontSize: 11.0,
                                height: 1.3,
                                color: isDark
                                    ? AppColors.coldWhite
                                    : AppColors.primaryTextLight,
                              ),
                            ),
                          if (availableRoutes.any(
                            (r) => r.isPubliclyPassable,
                          )) ...[
                            const SizedBox(height: 4.0),
                            const Text(
                              'Sugerencia: Se recomienda seleccionar una alternativa pública disponible.',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8.0),
            ] else if (validation.hasWarnings) ...[
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.5),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.hasUnconfirmedTransitability
                                ? 'Transitabilidad no confirmada'
                                : 'Precaución en el trazado',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          for (final w in validation.warnings)
                            Text(
                              '• $w',
                              style: TextStyle(
                                fontSize: 11.0,
                                height: 1.3,
                                color: isDark
                                    ? AppColors.coldWhite
                                    : AppColors.primaryTextLight,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8.0),
            ],

            // 5. Nota de responsabilidad vial y respaldo para motociclistas
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.two_wheeler_outlined,
                    size: 14.0,
                    color: isDark
                        ? AppColors.secondaryText
                        : AppColors.secondaryTextLight,
                  ),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      'Ruta calculada por red pública • No verificada en terreno. '
                      'Mantén Google Maps o Waze como respaldo ante obras o cierres.',
                      style: TextStyle(
                        fontSize: 10.0,
                        height: 1.25,
                        color: isDark
                            ? AppColors.secondaryText
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 6. Botones de acción rápida: Guardar favorita / Reportar vía
            if (onSaveFavorite != null || onReportIssue != null) ...[
              Row(
                children: [
                  if (onSaveFavorite != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSaveFavorite,
                        icon: const Icon(Icons.star_border, size: 16.0),
                        label: const Text(
                          'Favorita',
                          style: TextStyle(fontSize: 12.0),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF2E4D68)
                                : AppColors.silver,
                          ),
                          foregroundColor: isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight,
                        ),
                      ),
                    ),
                  if (onSaveFavorite != null && onReportIssue != null)
                    const SizedBox(width: 8.0),
                  if (onReportIssue != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReportIssue,
                        icon: const Icon(
                          Icons.report_problem_outlined,
                          size: 16.0,
                          color: AppColors.warning,
                        ),
                        label: const Text(
                          'Reportar',
                          style: TextStyle(
                            fontSize: 12.0,
                            color: AppColors.warning,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          side: BorderSide(
                            color: AppColors.warning.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10.0),
            ],

            // 7. Botón principal para iniciar navegación con la ruta seleccionada
            FilledButton.icon(
              onPressed: onStartNavigation,
              icon: Icon(
                current.isConfirmedRestricted
                    ? Icons.warning_amber_rounded
                    : Icons.navigation,
                size: 20.0,
              ),
              label: Text(
                current.isConfirmedRestricted
                    ? 'INICIAR RUTA (ACCESO RESTRINGIDO)'
                    : (availableRoutes.length > 1
                          ? 'INICIAR RUTA ${selectedRouteIndex + 1}'
                          : 'INICIAR NAVEGACIÓN'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                backgroundColor: current.isConfirmedRestricted
                    ? AppColors.error
                    : (isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy),
                foregroundColor: current.isConfirmedRestricted
                    ? Colors.white
                    : (isDark ? AppColors.nightBlue : Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteSelectorCard({
    required BuildContext context,
    required CalculatedRoute route,
    required int index,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final borderColor = isSelected
        ? (route.isConfirmedRestricted
              ? AppColors.error
              : (isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy))
        : (isDark ? const Color(0xFF264660) : AppColors.silver);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.0),
      child: Container(
        width: 155.0,
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isSelected
              ? (route.isConfirmedRestricted
                    ? AppColors.error.withValues(alpha: 0.15)
                    : (isDark
                          ? AppColors.cyanLuminous.withValues(alpha: 0.12)
                          : AppColors.surfaceNavy.withValues(alpha: 0.08)))
              : (isDark ? AppColors.cardNavy : AppColors.lightBackground),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: borderColor, width: isSelected ? 2.0 : 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ruta ${index + 1}',
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4.0),
                if (route.isConfirmedRestricted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: const Text(
                      'PRIVADA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                  )
                else if (route.hasUnconfirmedTransitability)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: const Text(
                      'REVISAR',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  )
                else if (route.isPreferred)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyanLuminous.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      'PREFERIDA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.cyanLuminous
                            : AppColors.surfaceNavy,
                      ),
                    ),
                  )
                else if (route.isFastest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: const Text(
                      'RÁPIDA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  )
                else if (route.isBalanced)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: const Text(
                      'EQUILIBRADA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9D95FF),
                      ),
                    ),
                  )
                else if (route.isShortest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyanLuminous.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      'CORTA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.cyanLuminous
                            : AppColors.electricBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3.0),
            Text(
              '${route.formattedDuration} • ${route.totalDistanceKm.toStringAsFixed(1)} km',
              style: TextStyle(
                fontSize: 11.0,
                color: isDark
                    ? AppColors.secondaryText
                    : AppColors.secondaryTextLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    String? diffText,
    required Color color,
  }) {
    return Column(
      children: [
        Text(label, style: AppTypography.badgeLabel.copyWith(fontSize: 8.5)),
        const SizedBox(height: 2.0),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15.0,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (diffText != null) ...[
              const SizedBox(width: 4.0),
              Text(
                '($diffText)',
                style: const TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
