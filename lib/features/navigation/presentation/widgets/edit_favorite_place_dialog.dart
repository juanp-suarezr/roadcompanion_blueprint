import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/saved_favorite_place.dart';

/// Modal o diálogo para guardar o editar un lugar favorito geográfico.
class EditFavoritePlaceDialog extends StatefulWidget {
  final SavedFavoritePlace? initialPlace;
  final Coordinates coordinates;
  final String? initialName;
  final String? initialAddress;

  const EditFavoritePlaceDialog({
    super.key,
    this.initialPlace,
    required this.coordinates,
    this.initialName,
    this.initialAddress,
  });

  static Future<SavedFavoritePlace?> show(
    BuildContext context, {
    SavedFavoritePlace? initialPlace,
    required Coordinates coordinates,
    String? initialName,
    String? initialAddress,
  }) {
    return showDialog<SavedFavoritePlace>(
      context: context,
      builder: (ctx) => EditFavoritePlaceDialog(
        initialPlace: initialPlace,
        coordinates: coordinates,
        initialName: initialName,
        initialAddress: initialAddress,
      ),
    );
  }

  @override
  State<EditFavoritePlaceDialog> createState() =>
      _EditFavoritePlaceDialogState();
}

class _EditFavoritePlaceDialogState extends State<EditFavoritePlaceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late FavoritePlaceCategory _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialPlace?.name ?? widget.initialName ?? '',
    );
    _notesController = TextEditingController(
      text: widget.initialPlace?.notes ?? widget.initialAddress ?? '',
    );
    _selectedCategory =
        widget.initialPlace?.category ?? FavoritePlaceCategory.custom;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(FavoritePlaceCategory cat) {
    switch (cat) {
      case FavoritePlaceCategory.home:
        return Icons.home_rounded;
      case FavoritePlaceCategory.work:
        return Icons.work_rounded;
      case FavoritePlaceCategory.family:
        return Icons.favorite_rounded;
      case FavoritePlaceCategory.farm:
        return Icons.agriculture_rounded;
      case FavoritePlaceCategory.viewpoint:
        return Icons.landscape_rounded;
      case FavoritePlaceCategory.gasStation:
        return Icons.local_gas_station_rounded;
      case FavoritePlaceCategory.custom:
        return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      title: Row(
        children: [
          Icon(
            widget.initialPlace != null
                ? Icons.edit_location_alt_rounded
                : Icons.star_rounded,
            color: AppColors.cyanLuminous,
            size: 26.0,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              widget.initialPlace != null
                  ? 'Editar favorito'
                  : 'Guardar en favoritos',
              style: AppTypography.sectionTitle.copyWith(
                color: isDark
                    ? AppColors.coldWhite
                    : AppColors.primaryTextLight,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicador de coordenadas
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardNavy : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.gps_fixed_rounded,
                    size: 16.0,
                    color: AppColors.cyanLuminous,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      '${widget.coordinates.latitude.toStringAsFixed(5)}, ${widget.coordinates.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontFamily: 'monospace',
                        color: isDark
                            ? AppColors.coldWhite
                            : AppColors.primaryTextLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),

            // Campo de Nombre
            Text(
              'Nombre del lugar *',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.secondaryTextDark
                    : AppColors.secondaryTextLight,
              ),
            ),
            const SizedBox(height: 6.0),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(
                color: isDark
                    ? AppColors.coldWhite
                    : AppColors.primaryTextLight,
              ),
              decoration: InputDecoration(
                hintText: 'Ej. Mi casa, Finca La Esperanza, Mirador...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppColors.secondaryTextDark
                      : AppColors.secondaryTextLight,
                ),
                filled: true,
                fillColor: isDark ? AppColors.cardNavy : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 12.0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // Selector de Categoría
            Text(
              'Categoría',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.secondaryTextDark
                    : AppColors.secondaryTextLight,
              ),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: FavoritePlaceCategory.values.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  avatar: Icon(
                    _getCategoryIcon(cat),
                    size: 16.0,
                    color: isSelected
                        ? Colors.black
                        : (isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight),
                  ),
                  label: Text(cat.label),
                  selected: isSelected,
                  selectedColor: AppColors.cyanLuminous,
                  backgroundColor: isDark
                      ? AppColors.cardNavy
                      : Colors.grey.shade200,
                  labelStyle: TextStyle(
                    fontSize: 12.0,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? Colors.black
                        : (isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16.0),

            // Campo de notas / referencia
            Text(
              'Notas o descripción (opcional)',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.secondaryTextDark
                    : AppColors.secondaryTextLight,
              ),
            ),
            const SizedBox(height: 6.0),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: TextStyle(
                color: isDark
                    ? AppColors.coldWhite
                    : AppColors.primaryTextLight,
              ),
              decoration: InputDecoration(
                hintText:
                    'Ej. Vereda San Isidro, vía destapada, portón negro...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppColors.secondaryTextDark
                      : AppColors.secondaryTextLight,
                ),
                filled: true,
                fillColor: isDark ? AppColors.cardNavy : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 12.0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(
              color: isDark
                  ? AppColors.secondaryTextDark
                  : AppColors.secondaryTextLight,
            ),
          ),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final finalName = name.isNotEmpty
                ? name
                : (_selectedCategory != FavoritePlaceCategory.custom
                      ? _selectedCategory.label
                      : 'Lugar favorito');

            final now = DateTime.now();
            final place = SavedFavoritePlace(
              id:
                  widget.initialPlace?.id ??
                  'fav_place_${now.millisecondsSinceEpoch}',
              name: finalName,
              coordinates: widget.coordinates,
              address: widget.initialAddress,
              category: _selectedCategory,
              createdAt: widget.initialPlace?.createdAt ?? now,
              updatedAt: now,
              notes: _notesController.text.trim().isNotEmpty
                  ? _notesController.text.trim()
                  : null,
            );

            Navigator.of(context).pop(place);
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.cyanLuminous,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
