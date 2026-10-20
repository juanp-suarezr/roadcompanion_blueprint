/// Resultado obtenido al seleccionar un archivo GPX desde el sistema operativo.
class GpxFileResult {
  /// Nombre del archivo seleccionado (por ejemplo, 'ruta_nevado.gpx').
  final String fileName;

  /// Contenido en texto del archivo GPX.
  final String content;

  /// Tamaño en bytes del archivo.
  final int sizeBytes;

  const GpxFileResult({
    required this.fileName,
    required this.content,
    required this.sizeBytes,
  });
}

/// Contrato abstracto para el selector de archivos GPX.
///
/// Permite desacoplar el acceso a la plataforma (Android/Flutter) del resto
/// de la aplicación y facilita la inyección de fakes o mocks en pruebas unitarias y de widgets.
abstract class GpxFilePicker {
  /// Abre el selector nativo para elegir un archivo `.gpx`.
  ///
  /// Retorna un [GpxFileResult] con el contenido y metadatos del archivo,
  /// o `null` si el usuario canceló la selección voluntariamente.
  Future<GpxFileResult?> pickGpxFile();
}
