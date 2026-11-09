import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Où sont gardées les sessions d'agent : un fichier JSON par session (écrit de
/// façon atomique), ou les préférences si les fichiers ne sont pas disponibles.
abstract class SessionStore {
  Future<List<Map<String, dynamic>>> loadAll();
  Future<void> save(String id, Map<String, dynamic> json);
  Future<void> delete(String id);

  static Future<SessionStore> create(Storage storage) async {
    if (!kIsWeb) {
      try {
        final dir = await getApplicationSupportDirectory();
        return FileSessionStore(Directory('${dir.path}/sessions'));
      } catch (_) {}
    }
    return PrefsSessionStore(storage);
  }
}

class FileSessionStore implements SessionStore {
  FileSessionStore(this.dir);

  final Directory dir;

  File _file(String id) => File('${dir.path}/$id.json');

  @override
  Future<List<Map<String, dynamic>>> loadAll() async {
    if (!await dir.exists()) return [];
    final out = <Map<String, dynamic>>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final raw = await e.readAsString();
        final j = raw.length > 200000
            ? await compute(jsonDecode, raw)
            : jsonDecode(raw);
        if (j is Map) out.add(Map<String, dynamic>.from(j));
      } catch (_) {
        // Fichier abîmé : ignoré.
      }
    }
    return out;
  }

  /// Les enregistrements en cours, par session : l'un après l'autre.
  final Map<String, Future<void>> _queue = {};
  int _n = 0;

  @override
  Future<void> save(String id, Map<String, dynamic> json) {
    final previous = _queue[id] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      // Les grosses sessions sont encodées hors du fil de l'interface.
      final raw = await compute(jsonEncode, json);
      await dir.create(recursive: true);
      final f = _file(id);
      final tmp = File('${f.path}.${_n++}.tmp');
      await tmp.writeAsString(raw, flush: true);
      await tmp.rename(f.path);
    });
    _queue[id] = next;
    next.whenComplete(() {
      if (identical(_queue[id], next)) _queue.remove(id);
    }).ignore();
    return next;
  }

  @override
  Future<void> delete(String id) async {
    // Après les enregistrements en cours, sinon la session reviendrait.
    await (_queue[id] ?? Future<void>.value()).catchError((_) {});
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}

class PrefsSessionStore implements SessionStore {
  PrefsSessionStore(this.storage);

  final Storage storage;

  List<String> get _ids =>
      (storage.readJson('session_ids') as List?)?.cast<String>() ?? [];

  @override
  Future<List<Map<String, dynamic>>> loadAll() async => [
    for (final id in _ids)
      if (storage.readJson('session_$id') case final Map j)
        Map<String, dynamic>.from(j),
  ];

  @override
  Future<void> save(String id, Map<String, dynamic> json) async {
    await storage.writeJson('session_$id', json);
    final ids = _ids;
    if (!ids.contains(id)) {
      await storage.writeJson('session_ids', [...ids, id]);
    }
  }

  @override
  Future<void> delete(String id) async {
    await storage.setString('session_$id', null);
    await storage.writeJson('session_ids', _ids..remove(id));
  }
}
