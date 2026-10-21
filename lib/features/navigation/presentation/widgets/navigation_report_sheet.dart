import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/navigation_issue_report.dart';
import '../../domain/services/smart_navigation_memory_service.dart';

/// Hoja modal para reportar incidencias viales en tiempo real (portones cerrados, giros prohibidos,
/// vías destapadas, baches severos) y almacenarlas en la memoria inteligente local.
class NavigationReportSheet extends StatefulWidget {
  final Coordinates location;
  final String? initialRoadSegment;
  final SmartNavigationMemoryService memoryService;

  const NavigationReportSheet({
    super.key,
    required this.location,
    this.initialRoadSegment,
    required this.memoryService,
  });

  static Future<NavigationIssueReport?> show(
    BuildContext context, {
    required Coordinates location,
    String? initialRoadSegment,
    required SmartNavigationMemoryService memoryService,
  }) {
    return showModalBottomSheet<NavigationIssueReport>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NavigationReportSheet(
        location: location,
        initialRoadSegment: initialRoadSegment,
        memoryService: memoryService,
      ),
    );
  }

  @override
  State<NavigationReportSheet> createState() => _NavigationReportSheetState();
}

class _NavigationReportSheetState extends State<NavigationReportSheet> {
  NavigationIssueType _selectedType = NavigationIssueType.lockedGate;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _roadController = TextEditingController();
  bool _isConfirmed = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoadSegment != null) {
      _roadController.text = widget.initialRoadSegment!;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _roadController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final description = _descriptionController.text.trim();
    final road = _roadController.text.trim();

    setState(() => _isSaving = true);

    final report = NavigationIssueReport(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      location: widget.location,
      type: _selectedType,
      roadSegment: road.isNotEmpty ? road : null,
      description: description.isNotEmpty
          ? description
          : _selectedType == NavigationIssueType.lockedGate
              ? 'Portón cerrado con candado / acceso privado'
              : 'Incidencia vial reportada',
      reportedAt: DateTime.now(),
      status: _isConfirmed
          ? ReportVerificationStatus.confirmed
          : ReportVerificationStatus.unconfirmed,
    );

    await widget.memoryService.addReport(report);

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).pop(report);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        top: 14.0,
        left: 20.0,
        right: 20.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tirador
            Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardNavy : AppColors.silver,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 14.0),

            // Título
            Row(
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  color: AppColors.error,
                  size: 22.0,
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    'REPORTAR INCIDENCIA VIAL',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20.0),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'Tus reportes se guardan en la memoria local de tu teléfono y enseñan al navegador a evitar vías cerradas.',
              style: TextStyle(
                fontSize: 12.0,
                color: isDark
                    ? AppColors.secondaryText
                    : AppColors.secondaryTextLight,
              ),
            ),
            const SizedBox(height: 14.0),

            // Selector de tipo de problema
            const Text(
              'TIPO DE PROBLEMA',
              style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8.0),
            _buildTypeSelector(isDark),
            const SizedBox(height: 14.0),

            // Nombre de la vía o sector
            TextField(
              controller: _roadController,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? AppColors.coldWhite : AppColors.primaryTextLight,
              ),
              decoration: const InputDecoration(
                labelText: 'Vía o sector (opcional)',
                hintText: 'Ej. Calle 35, Callejón lateral',
                prefixIcon: Icon(Icons.alt_route, size: 20.0),
              ),
            ),
            const SizedBox(height: 12.0),

            // Descripción o detalle
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? AppColors.coldWhite : AppColors.primaryTextLight,
              ),
              decoration: const InputDecoration(
                labelText: 'Detalle o comentario (opcional)',
                hintText: 'Ej. Portón con candado, paso cerrado a vehículos',
                prefixIcon: Icon(Icons.edit_note, size: 20.0),
              ),
            ),
            const SizedBox(height: 12.0),

            // Switch de confirmación de bloqueo
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isConfirmed,
              activeThumbColor: AppColors.error,
              title: const Text(
                'Confirmar como bloqueo activo',
                style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Si está activo, el motor de rutas buscará automáticamente desvíos y alternativas públicas para evitar este punto.',
                style: TextStyle(fontSize: 11.0),
              ),
              onChanged: (val) => setState(() => _isConfirmed = val),
            ),
            const SizedBox(height: 16.0),

            // Botón enviar reporte
            FilledButton.icon(
              onPressed: _isSaving ? null : _submitReport,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16.0,
                      height: 16.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Icon(Icons.check, size: 18.0),
              label: Text(_isSaving ? 'GUARDANDO...' : 'REGISTRAR REPORTE EN MEMORIA'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector(bool isDark) {
    final options = [
      (NavigationIssueType.lockedGate, 'Portón cerrado / Privada', Icons.lock_outline),
      (NavigationIssueType.wrongTurn, 'Giro incorrecto', Icons.turn_sharp_left),
      (NavigationIssueType.inaccessibleDestination, 'Destino inaccesible', Icons.block),
      (NavigationIssueType.unexpectedUnpaved, 'Vía destapada / Trocha', Icons.terrain),
      (NavigationIssueType.badRoadCondition, 'Vía en mal estado / Baches', Icons.warning_amber),
      (NavigationIssueType.other, 'Otro problema', Icons.more_horiz),
    ];

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: options.map((opt) {
        final isSelected = _selectedType == opt.$1;
        return FilterChip(
          selected: isSelected,
          avatar: Icon(
            opt.$3,
            size: 16.0,
            color: isSelected ? Colors.white : (isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy),
          ),
          label: Text(opt.$2),
          labelStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? AppColors.coldWhite : AppColors.primaryTextLight),
          ),
          backgroundColor: isDark ? AppColors.cardNavy : const Color(0xFFF1F6FA),
          selectedColor: AppColors.error,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedType = opt.$1;
                // Por defecto, portones y destinos inaccesibles se confirman como bloqueo activo
                if (opt.$1 == NavigationIssueType.lockedGate ||
                    opt.$1 == NavigationIssueType.inaccessibleDestination) {
                  _isConfirmed = true;
                }
              });
            }
          },
        );
      }).toList(),
    );
  }
}
