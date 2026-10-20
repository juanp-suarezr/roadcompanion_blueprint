import 'package:xml/xml.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/gpx_point.dart';
import '../../domain/entities/gpx_segment.dart';
import '../../domain/entities/imported_gpx_route.dart';

/// Excepción lanzada cuando un archivo GPX no puede ser parseado o no cumple
/// con las validaciones de estructura y contenido geográfico.
class GpxParseException implements Exception {
  final String message;
  final dynamic cause;

  const GpxParseException(this.message, [this.cause]);

  @override
  String toString() => 'GpxParseException: $message';
}

/// Parser puro y determinista de archivos GPX (GPS Exchange Format).
///
/// Soporta especificaciones GPX 1.0 y 1.1 mediante análisis XML estructurado
/// (sin expresiones regulares). Extrae tracks (`<trk>`), segmentos (`<trkseg>`),
/// rutas (`<rte>`) y puntos geográficos con elevación y marcas de tiempo opcionales.
///
/// Política de múltiples segmentos:
/// - Cada `<trkseg>` o `<rte>` se conserva como un [GpxSegment] independiente.
/// - La distancia geográfica se calcula estrictamente entre puntos consecutivos
///   dentro de un mismo segmento, sin conectar artificialmente segmentos separados.
class GpxParser {
  /// Tamaño máximo de archivo GPX admitido en memoria (15 MB).
  static const int maxFileSizeBytes = 15 * 1024 * 1024;

  const GpxParser();

  /// Parsea el contenido de un archivo GPX en texto plano y devuelve una [ImportedGpxRoute].
  ///
  /// Opcionalmente recibe [fallbackName] (por ejemplo, el nombre del archivo en disco).
  ///
  /// Lanza [GpxParseException] si el archivo está vacío, excede el tamaño máximo,
  /// contiene XML malformado, coordenadas inválidas o carece de puntos utilizables.
  ImportedGpxRoute parse(String gpxString, {String? fallbackName}) {
    if (gpxString.trim().isEmpty) {
      throw const GpxParseException('El archivo GPX está vacío.');
    }

    if (gpxString.length > maxFileSizeBytes) {
      throw const GpxParseException(
        'El archivo supera el tamaño máximo permitido de 15 MB.',
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(gpxString);
    } on XmlException catch (e) {
      throw GpxParseException(
        'El archivo contiene XML malformado o sintaxis inválida: ${e.message}',
        e,
      );
    } catch (e) {
      throw GpxParseException('Error al procesar la estructura XML: $e', e);
    }

    final gpxElement = document.findElements('gpx').firstOrNull;
    if (gpxElement == null) {
      throw const GpxParseException(
        'El documento XML no es un archivo GPX válido (falta el elemento raíz <gpx>).',
      );
    }

    // 1. Extraer nombre de la ruta o metadatos
    String? routeName;
    final metadataElement = gpxElement.findElements('metadata').firstOrNull;
    if (metadataElement != null) {
      routeName = metadataElement
          .findElements('name')
          .firstOrNull
          ?.innerText
          .trim();
    }

    final segments = <GpxSegment>[];

    // 2. Extraer tracks (<trk>) y segmentos (<trkseg>)
    final tracks = gpxElement.findElements('trk');
    for (final trk in tracks) {
      if (routeName == null || routeName.isEmpty) {
        final trkName = trk.findElements('name').firstOrNull?.innerText.trim();
        if (trkName != null && trkName.isNotEmpty) {
          routeName = trkName;
        }
      }

      final trksegs = trk.findElements('trkseg');
      for (final seg in trksegs) {
        final pts = _parsePoints(seg.findElements('trkpt'));
        if (pts.isNotEmpty) {
          segments.add(GpxSegment(pts));
        }
      }
    }

    // 3. Si no hay tracks o segmentos válidos, extraer rutas (<rte>)
    if (segments.isEmpty) {
      final routes = gpxElement.findElements('rte');
      for (final rte in routes) {
        if (routeName == null || routeName.isEmpty) {
          final rteName = rte
              .findElements('name')
              .firstOrNull
              ?.innerText
              .trim();
          if (rteName != null && rteName.isNotEmpty) {
            routeName = rteName;
          }
        }

        final pts = _parsePoints(rte.findElements('rtept'));
        if (pts.isNotEmpty) {
          segments.add(GpxSegment(pts));
        }
      }
    }

    // 4. Si aún no hay segmentos pero existen waypoints (<wpt>), extraerlos como segmento
    if (segments.isEmpty) {
      final wpts = gpxElement.findElements('wpt');
      final pts = _parsePoints(wpts);
      if (pts.isNotEmpty) {
        segments.add(GpxSegment(pts));
      }
    }

    if (segments.isEmpty) {
      throw const GpxParseException(
        'El archivo GPX no contiene puntos de recorrido utilizables (<trkpt>, <rtept> o <wpt>).',
      );
    }

    final effectiveName = (routeName != null && routeName.isNotEmpty)
        ? routeName
        : (fallbackName != null && fallbackName.trim().isNotEmpty)
        ? fallbackName.trim()
        : 'Ruta GPX';

    try {
      return ImportedGpxRoute(name: effectiveName, segments: segments);
    } on ArgumentError catch (e) {
      throw GpxParseException(e.message.toString(), e);
    }
  }

  List<GpxPoint> _parsePoints(Iterable<XmlElement> pointElements) {
    final points = <GpxPoint>[];

    for (final elem in pointElements) {
      final latAttr = elem.getAttribute('lat');
      final lonAttr = elem.getAttribute('lon');

      if (latAttr == null || lonAttr == null) {
        throw const GpxParseException(
          'Elemento de punto GPX sin atributos requeridos lat o lon.',
        );
      }

      final double? lat = double.tryParse(latAttr.trim());
      final double? lon = double.tryParse(lonAttr.trim());

      if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
        throw GpxParseException(
          'Coordenada geográfica no numérica o no finita: lat="$latAttr", lon="$lonAttr".',
        );
      }

      final Coordinates coordinates;
      try {
        coordinates = Coordinates(lat, lon);
      } on ArgumentError catch (e) {
        throw GpxParseException(
          'Coordenada fuera de rango geográfico permitido: ${e.message}',
          e,
        );
      }

      // Elevación opcional (<ele>)
      double? elevation;
      final eleElem = elem.findElements('ele').firstOrNull;
      if (eleElem != null) {
        final eleText = eleElem.innerText.trim();
        if (eleText.isNotEmpty) {
          final parsedEle = double.tryParse(eleText);
          if (parsedEle != null && parsedEle.isFinite) {
            elevation = parsedEle;
          }
        }
      }

      // Marca de tiempo opcional (<time>)
      DateTime? timestamp;
      final timeElem = elem.findElements('time').firstOrNull;
      if (timeElem != null) {
        final timeText = timeElem.innerText.trim();
        if (timeText.isNotEmpty) {
          timestamp = DateTime.tryParse(timeText);
        }
      }

      points.add(
        GpxPoint(
          coordinates: coordinates,
          elevation: elevation,
          time: timestamp,
        ),
      );
    }

    return points;
  }
}
