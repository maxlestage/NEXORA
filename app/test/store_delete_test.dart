import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/chat.dart';
import 'package:nexora/services/conversation_store.dart';

Conversation conv(String id) => Conversation(
  id: id,
  title: id,
  messages: [ChatMessage(role: Role.user, content: 'secret $id')],
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('nexora'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('une conversation supprimée pendant son enregistrement ne revient '
      'pas sur l\'appareil', () async {
    final store = FileConversationStore(dir);
    final c = conv('c1');
    // L'arrêt d'une réponse enregistre (sans attendre), puis on supprime.
    final saving = store.save(c);
    final deleting = store.delete('c1');
    await Future.wait([saving, deleting]);
    expect(await File('${dir.path}/c1.json').exists(), isFalse);
    expect(await store.loadMessages('c1'), isEmpty);
  });

  test(
    'tout effacer attend les enregistrements en cours : rien ne reste',
    () async {
      final store = FileConversationStore(dir);
      final pending = [
        store.save(conv('a')),
        store.save(conv('b')),
        store.saveIndex([conv('a'), conv('b')]),
      ];
      await store.deleteAll();
      await Future.wait(pending);
      expect(await dir.exists(), isFalse);
      expect(await store.sizeOnDisk(), 0);
    },
  );

  test(
    'enregistrer après une suppression recrée bien la conversation',
    () async {
      final store = FileConversationStore(dir);
      await store.save(conv('c1'));
      await store.delete('c1');
      await store.save(conv('c1'));
      expect(await store.loadMessages('c1'), hasLength(1));
    },
  );
}
