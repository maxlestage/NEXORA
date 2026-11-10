import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/models/chat.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/chat_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> chunk(String t) => utf8.encode(
  'data: ${jsonEncode({
    'choices': [
      {
        'delta': {'content': t},
      },
    ],
  })}\n\n',
);

/// Un modèle dont on contrôle chaque morceau de réponse.
(LlmClient, StreamController<List<int>>) live() {
  final out = StreamController<List<int>>();
  final llm = LlmClient(
    clientFactory: () => MockClient.streaming(
      (req, body) async => http.StreamedResponse(
        out.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    ),
  );
  return (llm, out);
}

Future<ChatState> chatWith(LlmClient llm) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  final settings = SettingsState(storage, llm);
  await settings.setDefaultModel(const ModelRef('groq', 'm'));
  final chat = ChatState(
    storage,
    settings,
    llm,
    store: PrefsConversationStore(storage),
  );
  await chat.ready;
  return chat;
}

Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 300 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arrêter une réponse garde tout le texte déjà reçu', () async {
    final (llm, out) = live();
    final chat = await chatWith(llm);
    final c = chat.create();
    chat.send(c.id, 'Dis bonjour');
    out.add(chunk('Bon'));
    await until(() => c.messages.last.content == 'Bon');
    // Arrive entre deux rafraîchissements de l'écran.
    out.add(chunk('jour à toi'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    chat.stop(c.id);
    expect(chat.isRunning(c.id), isFalse);
    expect(c.messages, hasLength(2));
    expect(c.messages.last.role, Role.assistant);
    expect(c.messages.last.content, 'Bonjour à toi');
    unawaited(out.close());
  });

  test('arrêter avant le premier mot ne laisse pas de bulle vide', () async {
    final (llm, out) = live();
    final chat = await chatWith(llm);
    final c = chat.create();
    chat.send(c.id, 'Dis bonjour');
    expect(c.messages, hasLength(2));
    chat.stop(c.id);
    expect(c.messages, hasLength(1));
    expect(c.messages.single.role, Role.user);
    unawaited(out.close());
  });
}
