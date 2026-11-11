import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';
import 'storage.dart';

/// Où sont rangées les conversations. Pensé pour un usage intensif : un index léger
/// (titres, aperçus) lu au démarrage, et les messages de chaque conversation dans
/// leur propre fichier, lus seulement à l'ouverture et réécrits seuls.
abstract class ConversationStore {
  Future<List<Conversation>> loadIndex();
  Future<List<ChatMessage>> loadMessages(String id);
  Future<void> save(Conversation c);
  Future<void> saveIndex(List<Conversation> all);
  Future<void> delete(String id);
  Future<void> deleteAll();

  /// Place occupée, en octets.
  Future<int> sizeOnDisk();

  /// Le stockage de l'appareil (fichiers), ou les préférences si les fichiers ne
  /// sont pas disponibles (web, tests).
  static Future<ConversationStore> create(Storage storage) async {
    if (!kIsWeb) {
      try {
        final dir = await getApplicationSupportDirectory();
        return FileConversationStore(Directory('${dir.path}/conversations'));
      } catch (_) {
        // Pas d'accès aux fichiers : on garde les préférences.
      }
    }
    return PrefsConversationStore(storage);
  }
}

/// Un fichier JSON par conversation et un index, écrits de façon atomique (fichier
/// temporaire puis renommage) pour ne jamais perdre une conversation.
class FileConversationStore implements ConversationStore {
  FileConversationStore(this.dir);

  final Directory dir;

  File get _index => File('${dir.path}/index.json');
  File _file(String id) => File('${dir.path}/$id.json');

  /// Les écritures en cours, par fichier : elles passent l'une après l'autre, jamais
  /// en même temps (sinon deux écritures pourraient se mélanger).
  final Map<String, Future<void>> _queue = {};
  int _n = 0;

  Future<void> _write(File f, String content) => _enqueue(f, () async {
    await dir.create(recursive: true);
    // Un fichier temporaire unique, puis un renommage (atomique).
    final tmp = File('${f.path}.${_n++}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  });

  /// Passe une opération sur un fichier après celles qui l'attendent déjà : une
  /// suppression attend la fin d'un enregistrement en cours, qui ne peut plus
  /// recréer le fichier ensuite (une conversation supprimée pendant qu'elle
  /// s'enregistrait restait sur l'appareil, invisible mais toujours là).
  Future<void> _enqueue(File f, Future<void> Function() op) {
    final previous = _queue[f.path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => op());
    _queue[f.path] = next;
    next.whenComplete(() {
      if (identical(_queue[f.path], next)) _queue.remove(f.path);
    }).ignore();
    return next;
  }

  @override
  Future<List<Conversation>> loadIndex() async {
    if (!await _index.exists()) return [];
    try {
      final j = jsonDecode(await _index.readAsString());
      return (j as List)
          .map((m) => Conversation.fromMeta(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ChatMessage>> loadMessages(String id) async {
    final f = _file(id);
    if (!await f.exists()) return [];
    try {
      final raw = await f.readAsString();
      // Gros fichiers : décodés hors du fil de l'interface.
      final list = raw.length > 200000
          ? await compute(_decodeMessages, raw)
          : _decodeMessages(raw);
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(Conversation c) async {
    if (!c.loaded) return;
    final raw = jsonEncode(c.messages.map((m) => m.toJson()).toList());
    await _write(_file(c.id), raw);
  }

  @override
  Future<void> saveIndex(List<Conversation> all) =>
      _write(_index, jsonEncode(all.map((c) => c.toMeta()).toList()));

  @override
  Future<void> delete(String id) {
    final f = _file(id);
    return _enqueue(f, () async {
      if (await f.exists()) await f.delete();
    });
  }

  @override
  Future<void> deleteAll() async {
    // Les enregistrements en cours finissent d'abord (sinon ils recréaient le
    // dossier et des conversations juste après l'effacement).
    while (_queue.isNotEmpty) {
      await Future.wait([for (final q in _queue.values) q.catchError((_) {})]);
    }
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<int> sizeOnDisk() async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}

List<ChatMessage> _decodeMessages(String raw) => (jsonDecode(raw) as List)
    .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
    .toList();

/// Repli sans fichiers : index et messages dans les préférences, une clé par
/// conversation.
class PrefsConversationStore implements ConversationStore {
  PrefsConversationStore(this.storage);

  final Storage storage;

  @override
  Future<List<Conversation>> loadIndex() async {
    final j = storage.readJson('conv_index');
    if (j is! List) return [];
    return j
        .map((m) => Conversation.fromMeta(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<List<ChatMessage>> loadMessages(String id) async {
    final j = storage.readJson('conv_$id');
    if (j is! List) return [];
    return j
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<void> save(Conversation c) async {
    if (!c.loaded) return;
    await storage.writeJson(
      'conv_${c.id}',
      c.messages.map((m) => m.toJson()).toList(),
    );
  }

  @override
  Future<void> saveIndex(List<Conversation> all) =>
      storage.writeJson('conv_index', all.map((c) => c.toMeta()).toList());

  @override
  Future<void> delete(String id) => storage.setString('conv_$id', null);

  @override
  Future<void> deleteAll() async {
    final index = await loadIndex();
    for (final c in index) {
      await delete(c.id);
    }
    await storage.setString('conv_index', null);
  }

  @override
  Future<int> sizeOnDisk() async {
    var total = (storage.getString('conv_index') ?? '').length;
    for (final c in await loadIndex()) {
      total += (storage.getString('conv_${c.id}') ?? '').length;
    }
    return total;
  }
}
