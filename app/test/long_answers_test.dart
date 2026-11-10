import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/models/chat.dart';
import 'package:nexora/models/usage.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/chat_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/quota_service.dart';
import 'package:nexora/state/usage_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une réponse en flux ; `finish` : la raison d'arrêt (null : aucune) ;
/// `done` : la ligne [DONE] finale.
http.StreamedResponse sse(
  String text, {
  String? finish,
  bool done = true,
  int? out,
}) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
            'finish_reason': ?finish,
          },
        ],
        if (out != null) 'usage': {'prompt_tokens': 300, 'completion_tokens': out},
      })}\n\n',
    ),
    if (done) utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

Future<(ChatState, List<Map>)> setup(
  List<http.StreamedResponse Function()> replies,
) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  final bodies = <Map>[];
  var i = 0;
  final llm = LlmClient(
    clientFactory: () => MockClient.streaming((req, body) async {
      bodies.add(jsonDecode(await body.bytesToString()) as Map);
      return replies[i++]();
    }),
  );
  final settings = SettingsState(storage, llm);
  final chat = ChatState(
    storage,
    settings,
    llm,
    usage: UsageState(storage),
    store: PrefsConversationStore(storage),
  );
  await chat.ready;
  return (chat, bodies);
}

Future<void> settle(ChatState chat, String id) async {
  for (var k = 0; k < 200 && chat.isRunning(id); k++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('réponse coupée par la limite (1 500 tokens) : la suite est demandée et '
      'raccordée, jusqu\'au bout', () async {
    final (chat, bodies) = await setup([
      () => sse(
        'Voici le code :\n\n```ts\nexport interface Item {',
        finish: 'length',
        out: 1500,
      ),
      () => sse(
        '```ts\nexport interface Item {\n  id: string;\n}\n```\n\nC\'est tout.',
        finish: 'stop',
        out: 40,
      ),
    ]);
    final c = chat.create(model: 'pollinations::openai-fast')..loaded = true;
    chat.send(c.id, 'Écris le fichier types.ts');
    await settle(chat, c.id);

    expect(bodies, hasLength(2));
    // La suite : la réponse déjà écrite, puis la consigne de continuer.
    final msgs = (bodies[1]['messages'] as List).cast<Map>();
    expect(msgs[msgs.length - 2]['role'], 'assistant');
    expect(
      msgs[msgs.length - 2]['content'],
      endsWith('export interface Item {'),
    );
    expect(msgs.last['content'], contains('coupée'));
    expect(msgs.last['content'], contains('sans rouvrir le bloc'));
    // Moins de réflexion pour la suite : les tokens vont au texte.
    expect(bodies[0]['reasoning_effort'], 'low');
    expect(bodies[1]['reasoning_effort'], 'low');

    final answer = c.messages.last;
    expect(answer.role, Role.assistant);
    expect(answer.error, isFalse);
    expect(
      answer.content,
      'Voici le code :\n\n```ts\nexport interface Item {\n  id: string;\n}\n'
      '```\n\nC\'est tout.',
    );
    expect('```'.allMatches(answer.content), hasLength(2));
    // Les tokens des deux parties sont comptés.
    expect(answer.tokensOut, 1540);
  });

  test(
    'connexion coupée sans signal de fin : la réponse continue aussi',
    () async {
      final (chat, bodies) = await setup([
        () => sse('Première moitié de la réponse, ', done: false),
        () => sse('et la seconde.', finish: 'stop'),
      ]);
      final c = chat.create(model: 'pollinations::openai-fast')..loaded = true;
      chat.send(c.id, 'Explique');
      await settle(chat, c.id);
      expect(bodies, hasLength(2));
      expect(
        c.messages.last.content,
        'Première moitié de la réponse, et la seconde.',
      );
    },
  );

  test('une réponse finie normalement n\'est pas prolongée', () async {
    final (chat, bodies) = await setup([
      () => sse('Bonjour !', finish: 'stop'),
    ]);
    final c = chat.create(model: 'pollinations::openai-fast')..loaded = true;
    chat.send(c.id, 'Salut');
    await settle(chat, c.id);
    expect(bodies, hasLength(1));
    expect(c.messages.last.content, 'Bonjour !');
  });

  test('pas de boucle sans fin : au plus 8 suites', () async {
    final (chat, bodies) = await setup([
      for (var k = 0; k < 20; k++) () => sse('morceau $k. ', finish: 'length'),
    ]);
    final c = chat.create(model: 'pollinations::openai-fast')..loaded = true;
    chat.send(c.id, 'Écris sans fin');
    await settle(chat, c.id);
    expect(bodies, hasLength(1 + ChatState.maxContinuations));
    expect(chat.isRunning(c.id), isFalse);
  });

  test(
    'Stop pendant une réponse coupée : aucune suite n\'est demandée',
    () async {
      final gate = Completer<void>();
      final (chat, bodies) = await setup([
        () => http.StreamedResponse(
          (() async* {
            await gate.future;
            yield* sse('Début', finish: 'length').stream;
          })(),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        () => sse('suite', finish: 'stop'),
      ]);
      final c = chat.create(model: 'pollinations::openai-fast')..loaded = true;
      chat.send(c.id, 'Long');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      chat.stop(c.id);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bodies, hasLength(1));
    },
  );

  group('raccord', () {
    test('le doublon du début est enlevé', () {
      expect(
        ChatState.stitch('Le chat dort sur le canapé', 'sur le canapé bleu.'),
        ' bleu.',
      );
    });
    test('un bloc de code rouvert est enlevé', () {
      expect(
        ChatState.stitch('```js\nconst a = 1;\n', '```js\nconst b = 2;\n```'),
        'const b = 2;\n```',
      );
      // Pas de bloc ouvert : il est gardé.
      expect(ChatState.stitch('Texte.\n', '```js\nx\n```'), '```js\nx\n```');
    });
    test('la ligne entamée reprise depuis son début', () {
      expect(
        ChatState.stitch(
          'a\nexport const db = getDat',
          'export const db = getDatabase(app);',
        ),
        'abase(app);',
      );
    });
    test('« Voici la suite : » est enlevé', () {
      expect(
        ChatState.stitch('Un texte', 'Voici la suite :\n et la fin.'),
        ' et la fin.',
      );
    });
  });

  group('raisons d\'arrêt', () {
    test('OpenAI, Anthropic, Ollama', () {
      expect(
        parseOpenAiSseLine(
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
        )!.truncated,
        isTrue,
      );
      expect(
        parseOpenAiSseLine(
          'data: {"choices":[{"delta":{"content":"x"},"finish_reason":"stop"}]}',
        )!.truncated,
        isFalse,
      );
      expect(
        parseAnthropicSseLine(
          'data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},'
          '"usage":{"output_tokens":9}}',
        )!.truncated,
        isTrue,
      );
      expect(
        parseOllamaLine(
          '{"message":{"content":""},"done":true,"done_reason":"length"}',
        )!.truncated,
        isTrue,
      );
    });
  });

  test(
    'le solde lu chez le fournisseur baisse à chaque réponse payante',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final usage = UsageState(storage);
      usage.of('anthropic').balance = const Balance(
        remaining: 5,
        total: 10,
        used: 5,
      );
      usage.recordUsage(
        'anthropic',
        model: 'claude-sonnet-5-5',
        usage: const TokenUsage(1000000, 0),
      );
      final b = usage.of('anthropic').balance!;
      expect(b.remaining, lessThan(5));
      expect(b.used, greaterThan(5));
    },
  );

  test('le solde est relu peu après une réponse', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    var calls = 0;
    final usage = UsageState(
      storage,
      quotas: FakeQuotas(() {
        calls++;
        return const Balance(remaining: 3.21, total: 10);
      }),
    );
    final p = providersCatalog.firstWhere((p) => p.id == 'openrouter');
    usage.refreshSoon(p, 'k', delay: Duration.zero);
    usage.refreshSoon(p, 'k', delay: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, 1, reason: 'deux réponses d\'affilée = une lecture');
    expect(usage.of('openrouter').balance!.remaining, 3.21);
  });
}

class FakeQuotas extends QuotaService {
  FakeQuotas(this.next);

  final Balance Function() next;

  @override
  Future<Balance?> fetchBalance(ProviderDef p, String? key) async => next();
}
