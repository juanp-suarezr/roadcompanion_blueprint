import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/navigation_session.dart';
import '../../domain/repositories/session_repository.dart';

/// Implementación local persistente de [SessionRepository] en el almacenamiento privado de la app.
class LocalSessionRepository implements SessionRepository {
  final Future<Directory> Function()? _directoryProvider;
  Directory? _cachedSessionsDir;

  LocalSessionRepository({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider;

  Future<Directory> _getSessionsDirectory() async {
    if (_cachedSessionsDir != null) return _cachedSessionsDir!;
    final baseDir = _directoryProvider != null
        ? await _directoryProvider()
        : await getApplicationDocumentsDirectory();

    final sessionsDir = Directory('${baseDir.path}/sessions');
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }
    _cachedSessionsDir = sessionsDir;
    return sessionsDir;
  }

  File _getSessionsFile(Directory dir) {
    return File('${dir.path}/sessions_log.json');
  }

  @override
  Future<List<NavigationSession>> getSessions() async {
    final dir = await _getSessionsDirectory();
    final file = _getSessionsFile(dir);

    if (!await file.exists()) {
      return [];
    }

    try {
      final jsonStr = await file.readAsString();
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final sessions = list
          .map(
            (item) => NavigationSession.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      return sessions;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveSession(NavigationSession session) async {
    final dir = await _getSessionsDirectory();
    final file = _getSessionsFile(dir);

    final sessions = await getSessions();
    final updated = List<NavigationSession>.from(sessions)
      ..removeWhere((s) => s.id == session.id)
      ..insert(0, session);

    final jsonList = updated.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  @override
  Future<void> deleteSession(String id) async {
    final dir = await _getSessionsDirectory();
    final file = _getSessionsFile(dir);

    final sessions = await getSessions();
    final updated = sessions.where((s) => s.id != id).toList();

    final jsonList = updated.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }
}
