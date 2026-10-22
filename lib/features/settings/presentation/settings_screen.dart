import 'package:flutter/material.dart';

import '../../../app/state/app_settings_state.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/estela_logo.dart';
import '../../../core/widgets/storm_badge.dart';

import '../../../features/navigation/domain/services/voice_navigation_service.dart';
import '../../../features/navigation/infrastructure/services/flutter_blue_plus_tripper_service.dart';
import '../../../features/navigation/infrastructure/services/flutter_tts_voice_navigation_service.dart';
import '../../../features/navigation/presentation/screens/tripper_diagnostic_screen.dart';

/// Pantalla de Ajustes de Road Companion.
///
/// Gestiona la selección de tema (Sistema / Claro / Oscuro), el perfil
/// personalizado de la motocicleta, indicaciones por voz TTS y el estado transparente de dispositivos externos.
class SettingsScreen extends StatefulWidget {
  final VoiceNavigationService? voiceService;

  const SettingsScreen({super.key, this.voiceService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _customNameController;
  late final VoiceNavigationService _voiceService;
  bool _initialized = false;
  bool _isTestingVoice = false;
  String? _voiceTestMessage;

  @override
  void initState() {
    super.initState();
    _voiceService = widget.voiceService ?? FlutterTtsVoiceNavigationService();
    _voiceService.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = AppSettingsScope.of(context);
      _brandController = TextEditingController(text: settings.motorcycleBrand);
      _modelController = TextEditingController(text: settings.motorcycleModel);
      _customNameController = TextEditingController(
        text: settings.motorcycleCustomName,
      );
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _customNameController.dispose();
    if (widget.voiceService == null) {
      _voiceService.dispose();
    }
    super.dispose();
  }

  Future<void> _handleTestVoice() async {
    setState(() {
      _isTestingVoice = true;
      _voiceTestMessage = 'Emitiendo locución de prueba en español...';
    });

    final success = await _voiceService.testVoice(
      sampleText: 'REstelar: audio de navegación por voz listo en español.',
    );

    if (mounted) {
      setState(() {
        _isTestingVoice = false;
        _voiceTestMessage = success
            ? 'Prueba emitida correctamente.'
            : 'Fallo al reproducir. Verifica que los Servicios de Voz de Google estén activos.';
      });
    }
  }

  void _saveMotorcycleProfile() {
    final settings = AppSettingsScope.read(context);
    settings.updateMotorcycleProfile(
      brand: _brandController.text,
      model: _modelController.text,
      customName: _customNameController.text,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20.0),
            SizedBox(width: 10.0),
            Text('Perfil de motocicleta actualizado.'),
          ],
        ),
        backgroundColor: AppColors.deepBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = AppSettingsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          children: [
            // --- SECCIÓN 1: APARIENCIA ---
            _buildSectionHeader('APARIENCIA', Icons.palette_outlined),
            const SizedBox(height: 10.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tema visual',
                      style: AppTypography.sectionTitle.copyWith(
                        fontSize: 16.0,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Personaliza la paleta para optimizar el contraste de día o de noche.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    // Selector Segmentado de Tema
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text('Sistema'),
                          icon: Icon(Icons.brightness_auto, size: 18.0),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Claro'),
                          icon: Icon(Icons.light_mode, size: 18.0),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Oscuro'),
                          icon: Icon(Icons.dark_mode, size: 18.0),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (newSelection) {
                        settings.setThemeMode(newSelection.first);
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.comfortable,
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    // Vistas previas visuales compactas
                    Row(
                      children: [
                        Expanded(
                          child: _buildThemePreviewCard(
                            title: 'Día (Claro)',
                            bgColor: AppColors.lightBackground,
                            surfaceColor: Colors.white,
                            accentColor: AppColors.deepBlue,
                            textColor: AppColors.primaryTextLight,
                            isSelected: settings.themeMode == ThemeMode.light,
                            onTap: () => settings.setThemeMode(ThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: _buildThemePreviewCard(
                            title: 'Noche (Oscuro)',
                            bgColor: AppColors.stormNavy,
                            surfaceColor: AppColors.darkSurface,
                            accentColor: AppColors.accentBlue,
                            textColor: AppColors.primaryTextDark,
                            isSelected: settings.themeMode == ThemeMode.dark,
                            onTap: () => settings.setThemeMode(ThemeMode.dark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // --- SECCIÓN 2: MOTOCICLETA ---
            _buildSectionHeader('MOTOCICLETA', Icons.two_wheeler),
            const SizedBox(height: 10.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Perfil de tu máquina',
                      style: AppTypography.sectionTitle.copyWith(
                        fontSize: 16.0,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Compatible con cualquier marca, modelo o personalización.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    // Nombre personalizado
                    TextField(
                      controller: _customNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre / Apodo de la moto',
                        hintText: 'Ej. StormBlue',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12.0),

                    // Marca
                    TextField(
                      controller: _brandController,
                      decoration: const InputDecoration(
                        labelText: 'Marca',
                        hintText: 'Ej. Royal Enfield, Yamaha, Honda...',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 12.0),

                    // Modelo
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'Modelo',
                        hintText: 'Ej. Meteor 350, Himalayan, MT-03...',
                        prefixIcon: Icon(Icons.motorcycle_outlined),
                      ),
                    ),
                    const SizedBox(height: 16.0),

                    ElevatedButton.icon(
                      onPressed: _saveMotorcycleProfile,
                      icon: const Icon(Icons.save_outlined, size: 20.0),
                      label: const Text('Guardar perfil de motocicleta'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // --- SECCIÓN: VOZ Y AUDIO DE NAVEGACIÓN ---
            _buildSectionHeader('VOZ Y NAVEGACIÓN', Icons.record_voice_over_outlined),
            const SizedBox(height: 10.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Indicaciones de voz (TTS)',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        StormBadge(
                          label: _formatVoiceStatus(_voiceService.status),
                          variant: _getVoiceBadgeVariant(_voiceService.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      _voiceService.statusMessage ??
                          'Emite instrucciones por voz en español adaptadas para intercomunicadores de casco Bluetooth.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14.0),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                            ),
                            onPressed: _isTestingVoice ? null : _handleTestVoice,
                            icon: Icon(
                              _isTestingVoice
                                  ? Icons.hourglass_top_rounded
                                  : Icons.volume_up_rounded,
                              size: 18.0,
                            ),
                            label: Text(_isTestingVoice ? 'Emitiendo...' : 'Probar voz'),
                          ),
                        ),
                        const SizedBox(width: 10.0),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                            ),
                            onPressed: () {
                              setState(() {
                                _voiceService.toggleMute();
                              });
                            },
                            icon: Icon(
                              _voiceService.isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              size: 18.0,
                            ),
                            label: Text(_voiceService.isMuted ? 'Desilenciar' : 'Silenciar'),
                          ),
                        ),
                      ],
                    ),
                    if (_voiceTestMessage != null) ...[
                      const SizedBox(height: 10.0),
                      Text(
                        _voiceTestMessage!,
                        style: const TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12.0),
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18.0,
                            color: AppColors.cyanLuminous,
                          ),
                          SizedBox(width: 10.0),
                          Expanded(
                            child: Text(
                              'Para escuchar las instrucciones en tu intercomunicador, vincula tu casco por Bluetooth al teléfono y mantén el volumen multimedia activo.',
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // --- SECCIÓN 3: DISPOSITIVOS EXTERNOS ---
            _buildSectionHeader('DISPOSITIVOS', Icons.devices_other),
            const SizedBox(height: 10.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pantalla externa / Pod',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        StormBadge(
                          label: 'PENDIENTE',
                          variant: StormBadgeVariant.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      'La integración por Bluetooth con pantallas de manillar y pods de navegación externa está en proceso de desarrollo arquitectónico.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: isDark
                              ? AppColors.cyanLuminous
                              : AppColors.surfaceNavy,
                          foregroundColor:
                              isDark ? AppColors.nightBlue : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(
                          Icons.bluetooth_searching_rounded,
                          size: 18.0,
                        ),
                        label: const Text(
                          'Conectar mi Tripper / Laboratorio BLE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TripperDiagnosticScreen(
                              bleService: FlutterBluePlusTripperService(),
                              voiceService: _voiceService,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // --- SECCIÓN 4: ACERCA DE ---
            _buildSectionHeader('INFORMACIÓN', Icons.info_outline),
            const SizedBox(height: 10.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const EstelaLogo(
                          size: 44.0,
                          variant: EstelaLogoVariant.emblem,
                        ),
                        const SizedBox(width: 14.0),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'REstelar',
                              style: TextStyle(
                                fontSize: 17.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              'Versión 0.1.0 • Navegador complementario',
                              style: TextStyle(
                                fontSize: 12.0,
                                color: AppColors.secondaryTextLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14.0),
                    Text(
                      'TU RUMBO. TU HISTORIA.\nDiseñada para acompañarte en cada kilómetro de carretera. Una aplicación sobria, elegante y confiable pensada por y para motociclistas.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30.0),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16.0, color: AppColors.steelBlue),
        const SizedBox(width: 6.0),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.steelBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildThemePreviewCard({
    required String title,
    required Color bgColor,
    required Color surfaceColor,
    required Color accentColor,
    required Color textColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF435A6D),
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, size: 16.0, color: accentColor),
              ],
            ),
            const SizedBox(height: 8.0),
            Container(
              height: 24.0,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6.0,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(6.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Container(
                    width: 32.0,
                    height: 5.0,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVoiceStatus(VoiceServiceStatus status) {
    switch (status) {
      case VoiceServiceStatus.uninitialized:
        return 'INICIALIZANDO';
      case VoiceServiceStatus.initializing:
        return 'INICIALIZANDO';
      case VoiceServiceStatus.ready:
        return 'VOZ LISTA';
      case VoiceServiceStatus.muted:
        return 'SILENCIADA';
      case VoiceServiceStatus.error:
        return 'ERROR DE VOZ';
    }
  }

  StormBadgeVariant _getVoiceBadgeVariant(VoiceServiceStatus status) {
    switch (status) {
      case VoiceServiceStatus.ready:
        return StormBadgeVariant.success;
      case VoiceServiceStatus.muted:
        return StormBadgeVariant.neutral;
      case VoiceServiceStatus.initializing:
      case VoiceServiceStatus.uninitialized:
        return StormBadgeVariant.info;
      case VoiceServiceStatus.error:
        return StormBadgeVariant.warning;
    }
  }
}

