import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse sse(String text) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

/// Un modèle qui cherche sans fin une fonction qui n'existe pas.
const same =
    '```json\n{"tool": "search_code", "args": {"query": "compare_versions", '
    '"path": "src"}}\n```';

const done =
    '```json\n{"tool": "finish", "args": {"summary": "Fait autrement"}}\n```';

void main() {
  setUp(() => AgentRun.checks = false);
  tearDown(() => AgentRun.checks = true);

  late List<String> prompts;

  AgentRun build() {
    prompts = [];
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          final msgs = j['messages'] as List;
          prompts.add((msgs.last as Map)['content'].toString());
          // Le second modèle, lui, change d'approche.
          return sse(j['model'] == 'm2' ? done : same);
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Ajoute un test pour la fonction qui compare les versions',
    );
  }

  test('même action répétée : la relance devient ferme et dit que la cible '
      'n\'existe pas, puis la session s\'arrête clairement', () async {
    final run = build();
    await run.run();
    expect(run.running, isFalse);
    expect(run.steps.last.text, contains('en boucle'));
    // Première relance douce, puis une relance ferme qui change de cap.
    expect(prompts.any((p) => p.contains('inutile de la répéter')), isTrue);
    expect(prompts.any((p) => p.contains('N\'EXISTE PAS')), isTrue);
    expect(prompts.any((p) => p.contains('Choisis une AUTRE action')), isTrue);
  });

  test(
    'même action répétée : un autre modèle prend la suite et termine',
    () async {
      final run = build()
        ..fallback = (e, tried) async => tried.contains('groq::m2')
            ? null
            : (providersCatalog.firstWhere((p) => p.id == 'groq'), 'k', 'm2');
      await run.run();
      expect(run.model, 'm2');
      expect(run.summary, 'Fait autrement');
      expect(run.steps.any((s) => s.text.contains('Je continue avec')), isTrue);
      expect(
        run.steps.any((s) => s.text.contains('en boucle : arrêté')),
        isFalse,
      );
    },
  );
}
