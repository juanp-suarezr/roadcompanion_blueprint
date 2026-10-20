import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'gpx_file_picker.dart';

/// Implementación real del selector de archivos para Android y Flutter
/// basada en el paquete `file_picker`.
class NativeGpxFilePicker implements GpxFilePicker {
  final FilePicker? _picker;

  NativeGpxFilePicker({FilePicker? picker}) : _picker = picker;

  FilePicker get _platformPicker {
    if (_picker != null) return _picker;
    return FilePicker.platform;
  }

  @override
  Future<GpxFileResult?> pickGpxFile() async {
    final result = await _platformPicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final platformFile = result.files.first;
    final fileName = platformFile.name;
    final int sizeBytes = platformFile.size;

    String content;
    if (platformFile.bytes != null) {
      try {
        content = utf8.decode(platformFile.bytes!);
      } on FormatException {
        // Fallback a decodificación latin1 si el archivo contiene caracteres especiales con codificación heredada
        content = latin1.decode(platformFile.bytes!);
      }
    } else if (platformFile.path != null) {
      final file = File(platformFile.path!);
      try {
        content = await file.readAsString(encoding: utf8);
      } on FormatException {
        content = await file.readAsString(encoding: latin1);
      }
    } else {
      throw const FileSystemException(
        'No se pudo acceder a los datos binarios ni a la ruta del archivo seleccionado.',
      );
    }

    return GpxFileResult(
      fileName: fileName,
      content: content,
      sizeBytes: sizeBytes,
    );
  }
}
