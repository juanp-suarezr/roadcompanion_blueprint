import 'dart:io';

import '../../domain/entities/imported_gpx_route.dart';
import '../parsers/gpx_parser.dart';
import 'gpx_file_picker.dart';
import 'native_gpx_file_picker.dart';

/// Resultado del flujo de importación de un archivo GPX.
sealed class GpxImportResult {
  const GpxImportResult();

  factory GpxImportResult.success(
    ImportedGpxRoute route, {
    String fileName,
    String rawContent,
  }) = GpxImportSuccess;

  factory GpxImportResult.cancelled() = GpxImportCancelled;

  factory GpxImportResult.failure(String message) = GpxImportFailure;
}

class GpxImportSuccess extends GpxImportResult {
  final ImportedGpxRoute route;
  final String fileName;
  final String rawContent;

  const GpxImportSuccess(
    this.route, {
    this.fileName = 'ruta.gpx',
    this.rawContent = '',
  });
}

class GpxImportCancelled extends GpxImportResult {
  const GpxImportCancelled();
}

class GpxImportFailure extends GpxImportResult {
  final String message;
  const GpxImportFailure(this.message);
}

/// Servicio desacoplado para coordinar la selección, lectura y parseo de archivos GPX.
class GpxImportService {
  final GpxFilePicker _filePicker;
  final GpxParser _parser;

  GpxImportService({GpxFilePicker? filePicker, GpxParser? parser})
    : _filePicker = filePicker ?? NativeGpxFilePicker(),
      _parser = parser ?? const GpxParser();

  /// Abre el selector de archivos, lee el contenido y parsea la ruta GPX.
  Future<GpxImportResult> importGpx() async {
    try {
      final fileResult = await _filePicker.pickGpxFile();

      if (fileResult == null) {
        return const GpxImportCancelled();
      }

      final route = _parser.parse(
        fileResult.content,
        fallbackName: fileResult.fileName,
      );

      return GpxImportSuccess(
        route,
        fileName: fileResult.fileName,
        rawContent: fileResult.content,
      );
    } on GpxParseException catch (e) {
      return GpxImportFailure(e.message);
    } on FileSystemException catch (e) {
      return GpxImportFailure(
        'Error del sistema al leer el archivo: ${e.message}',
      );
    } catch (e) {
      return GpxImportFailure('No se pudo procesar el archivo GPX: $e');
    }
  }

  /// Parsea directamente una cadena GPX en memoria (útil para pruebas y adaptadores).
  ImportedGpxRoute parseString(String gpxContent, {String? fallbackName}) {
    return _parser.parse(gpxContent, fallbackName: fallbackName);
  }
}
