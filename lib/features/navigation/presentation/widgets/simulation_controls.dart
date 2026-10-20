import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Barra de controles táctiles para la simulación de navegación.
///
/// Permite reproducir, pausar, avanzar paso a paso y reiniciar la ruta demostrativa.
class SimulationControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onStepForward;
  final VoidCallback onStepBackward;
  final VoidCallback onReset;

  const SimulationControls({
    super.key,
    required this.isPlaying,
    required this.onTogglePlayPause,
    required this.onStepForward,
    required this.onStepBackward,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark ? const Color(0xFF263A48) : const Color(0xFFD7DFE8),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Reiniciar al inicio
          IconButton(
            icon: const Icon(Icons.replay),
            iconSize: 24.0,
            color: isDark ? AppColors.silver : AppColors.deepBlue,
            tooltip: 'Reiniciar simulación',
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            onPressed: onReset,
          ),

          // Paso atrás
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 28.0,
            color: isDark ? AppColors.silver : AppColors.deepBlue,
            tooltip: 'Paso anterior',
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            onPressed: onStepBackward,
          ),

          // Botón principal Reproducir / Pausar
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.accentBlue
                  : AppColors.deepBlue,
              foregroundColor: isDark ? AppColors.stormNavy : Colors.white,
              minimumSize: const Size(64.0, 52.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
            ),
            onPressed: onTogglePlayPause,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 26.0),
                const SizedBox(width: 6.0),
                Text(
                  isPlaying ? 'Pausar' : 'Simular',
                  style: const TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Paso adelante
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 28.0,
            color: isDark ? AppColors.silver : AppColors.deepBlue,
            tooltip: 'Paso siguiente',
            constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
            onPressed: onStepForward,
          ),
        ],
      ),
    );
  }
}
