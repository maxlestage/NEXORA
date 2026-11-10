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

/// Un modèle bloqué : il redit la demande et sa réflexion, sans jamais d'action.
const stuck =
    '```json\n{"demande": "Ajoute une fonction somme", '
    '"thought": "Accès refusé, je ne peux rien faire."}\n```';

const done =
    '```json\n{"tool": "finish", "args": {"summary": "Fait autrement"}}\n```';

void main() {
  late int asked;

  AgentRun build() {
    asked = 0;
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          asked++;
          // Le second modèle, lui, agit.
          return sse(j['model'] == 'm2' ? done : stuck);
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
      task: 'Ajoute une fonction somme',
    );
  }

  test('réflexion sans action : affichée lisiblement, pas en JSON brut', () {
    expect(
      actionlessThought(stuck),
      '🎯 Ajoute une fonction somme\nAccès refusé, je ne peux rien faire.',
    );
    expect(actionlessThought('Je réfléchis encore.'), isNull);
    expect(parseToolCalls(stuck), isEmpty);
  });

  test('modèle qui ne choisit jamais d\'action : la session s\'arrête vite, '
      'avec une explication, au lieu de gaspiller toutes ses étapes', () async {
    final run = build();
    await run.run();
    expect(run.finished, isFalse);
    expect(run.running, isFalse);
    expect(run.steps.last.text, contains('sans jamais choisir d\'action'));
    // Quelques essais, pas les dizaines d'étapes permises.
    expect(asked, lessThan(10));
    final thoughts = run.steps.where((s) => s.kind == StepKind.thought);
    expect(thoughts, isNotEmpty);
    expect(thoughts.any((s) => s.text.contains('```')), isFalse);
  });

  test('modèle bloqué : un autre modèle prend la suite et termine', () async {
    final run = build()
      ..fallback = (e, tried) async => tried.contains('groq::m2')
          ? null
          : (providersCatalog.firstWhere((p) => p.id == 'groq'), 'k', 'm2');
    await run.run();
    expect(run.model, 'm2');
    expect(run.summary, 'Fait autrement');
    expect(run.steps.any((s) => s.text.contains('Je continue avec')), isTrue);
  });
}
