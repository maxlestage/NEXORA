import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/chat.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/chat_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réponse en flux au format OpenAI, morceau par morceau.
http.StreamedResponse sse(List<String> chunks, {int status = 200}) =>
    http.StreamedResponse(
      Stream.fromIterable([
        for (final c in chunks)
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': c},
                },
              ],
            })}\n\n',
          ),
        utf8.encode('data: [DONE]\n\n'),
      ]),
      status,
      headers: {'content-type': 'text/event-stream'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  P(String id) => providersCatalog.firstWhere((p) => p.id == id);

  group('stockage des conversations', () {
    test('fichiers : index léger et messages à part', () async {
      final dir = await Directory.systemTemp.createTemp('nexora');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileConversationStore(dir);
      final c = Conversation(
        id: 'c1',
        title: 'Gros projet',
        messages: [
          for (var i = 0; i < 50; i++)
            ChatMessage(role: Role.user, content: 'message $i'),
        ],
      );
      await store.save(c);
      await store.saveIndex([c]);

      final index = await store.loadIndex();
      expect(index.single.title, 'Gros projet');
      expect(index.single.loaded, isFalse);
      expect(index.single.messageCount, 50);
      expect(index.single.preview, 'message 49');
      expect(index.single.messages, isEmpty);

      final messages = await store.loadMessages('c1');
      expect(messages, hasLength(50));
      expect(await store.sizeOnDisk(), greaterThan(0));
      // Une conversation non chargée n'écrase jamais ses messages.
      await store.save(index.single);
      expect(await store.loadMessages('c1'), hasLength(50));

      await store.delete('c1');
      expect(await store.loadMessages('c1'), isEmpty);
    });

    test(
      'migration des anciennes conversations puis chargement à la demande',
      () async {
        SharedPreferences.setMockInitialValues({
          'conversations': jsonEncode([
            {
              'id': 'old',
              'title': 'Ancienne',
              'messages': [
                {'role': 'user', 'content': 'Bonjour'},
                {'role': 'assistant', 'content': 'Salut !'},
              ],
            },
          ]),
        });
        final storage = await Storage.open();
        final settings = SettingsState(storage, LlmClient());
        final chat = ChatState(
          storage,
          settings,
          LlmClient(),
          store: PrefsConversationStore(storage),
        );
        await chat.ready;
        expect(storage.getString('conversations'), isNull);
        expect(chat.conversations.single.title, 'Ancienne');

        // Au prochain lancement, seul l'index est lu.
        final again = ChatState(
          storage,
          settings,
          LlmClient(),
          store: PrefsConversationStore(storage),
        );
        await again.ready;
        final c = again.byId('old')!;
        expect(c.loaded, isFalse);
        expect(c.messageCount, 2);
        expect(c.preview, 'Salut !');
        await again.ensureLoaded('old');
        expect(again.byId('old')!.messages.last.content, 'Salut !');
      },
    );

    test(
      'ménage : les vieilles conversations partent, pas les épinglées',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = await Storage.open();
        final chat = ChatState(
          storage,
          SettingsState(storage, LlmClient()),
          LlmClient(),
          store: PrefsConversationStore(storage),
        );
        await chat.ready;
        final old = chat.create()..updated = DateTime(2020);
        final pinned = chat.create()
          ..updated = DateTime(2020)
          ..pinned = true;
        chat.create();
        expect(chat.deleteOlderThan(30), 1);
        expect(chat.byId(old.id), isNull);
        expect(chat.byId(pinned.id), isNotNull);
        expect(chat.conversations, hasLength(2));
      },
    );
  });

  group('mémoire envoyée au modèle', () {
    List<ChatMessage> convo(int n) => [
      for (var i = 0; i < n; i++)
        ChatMessage(
          role: i.isEven ? Role.user : Role.assistant,
          content: 'x' * 400, // ≈ 100 tokens
        ),
    ];

    test('seuls les messages récents partent', () {
      final (history, dropped) = ChatState.recentHistory(convo(100), 1000);
      expect(history.length, lessThan(12));
      expect(dropped, 100 - history.length);
    });

    test('0 = toute la conversation', () {
      final (history, dropped) = ChatState.recentHistory(convo(100), 0);
      expect(history, hasLength(100));
      expect(dropped, 0);
    });

    test('le dernier message part même s\'il est énorme', () {
      final big = [ChatMessage(role: Role.user, content: 'y' * 100000)];
      final (history, _) = ChatState.recentHistory(big, 1000);
      expect(history, hasLength(1));
    });
  });

  group('réseau', () {
    test('503 puis succès : nouvel essai automatique', () async {
      var calls = 0;
      final client = MockClient.streaming((req, body) async {
        await body.drain<void>();
        calls++;
        if (calls == 1) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"overloaded"}')),
            503,
            headers: {'retry-after': '1'},
          );
        }
        return sse(['Bon', 'jour']);
      });
      final delays = <Duration>[];
      final llm = LlmClient(
        clientFactory: () => client,
        retryDelay: (attempt, after) {
          final d = LlmClient.defaultRetryDelay(attempt, after);
          delays.add(d);
          return Duration.zero;
        },
      );
      final out = await llm.complete(
        provider: P('groq'),
        apiKey: 'k',
        model: 'm',
        messages: const [LlmMessage('user', 'a')],
      );
      expect(out, 'Bonjour');
      expect(calls, 2);
      expect(delays.single, const Duration(seconds: 1));
    });

    test('toujours saturé : l\'erreur finit par remonter', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('{"error":{"message":"rate limited"}}', 429);
      });
      final llm = LlmClient(
        clientFactory: () => client,
        retryDelay: (_, _) => Duration.zero,
      );
      await expectLater(
        llm.complete(
          provider: P('groq'),
          apiKey: 'k',
          model: 'm',
          messages: const [LlmMessage('user', 'a')],
        ),
        throwsA(isA<LlmException>()),
      );
      expect(calls, 1 + LlmClient.maxRetries);
    });

    test('flux muet : coupé au bout du délai', () async {
      final client = MockClient.streaming((req, body) async {
        final never = StreamController<List<int>>();
        never.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"Dé"}}]}\n\n'),
        );
        return http.StreamedResponse(
          never.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final llm = LlmClient(
        clientFactory: () => client,
        idleTimeout: const Duration(milliseconds: 100),
      );
      final got = <String>[];
      Object? error;
      await llm
          .stream(
            provider: P('groq'),
            apiKey: 'k',
            model: 'm',
            messages: const [LlmMessage('user', 'a')],
          )
          .handleError((Object e) => error = e)
          .forEach((d) => got.add(d.text));
      expect(got.join(), 'Dé');
      expect(error, isA<LlmException>());
    });
  });

  test('flux rapide : l\'écran est rafraîchi bien moins souvent', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final client = MockClient.streaming((req, body) async {
      await body.drain<void>();
      return sse([for (var i = 0; i < 400; i++) 'a']);
    });
    final llm = LlmClient(clientFactory: () => client);
    final chat = ChatState(
      storage,
      SettingsState(storage, llm),
      llm,
      store: PrefsConversationStore(storage),
    );
    await chat.ready;
    final c = chat.create();
    var notifications = 0;
    chat.addListener(() => notifications++);
    chat.send(c.id, 'Salut');
    while (chat.isRunning(c.id)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.messages.last.content, 'a' * 400);
    expect(notifications, lessThan(40));
    // Enregistrée dès la fin de la réponse.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final saved = await PrefsConversationStore(storage).loadMessages(c.id);
    expect(saved.last.content, 'a' * 400);
    chat.dispose();
  });

  test('agent : les anciens résultats d\'outils sont raccourcis', () {
    final history = [
      const LlmMessage('user', 'Tâche'),
      for (var i = 0; i < 12; i++) ...[
        const LlmMessage('assistant', '{"tool":"read_file"}'),
        LlmMessage('user', 'Résultat de read_file :\n${'z' * 5000}'),
      ],
    ];
    AgentRun.compactHistory(history);
    final results = history
        .where((m) => m.content.startsWith('Résultat de'))
        .toList();
    expect(results.take(4).every((m) => m.content.length < 600), isTrue);
    expect(results.skip(4).every((m) => m.content.length > 5000), isTrue);
  });
}
