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

const other =
    '```json\n{"tool": "search_code", "args": {"query": "fn compare"}}\n```';

const done =
    '```json\n{"tool": "finish", "args": {"summary": "Fait autrement"}}\n```';

void main() {
  setUp(() => AgentRun.checks = false);
  tearDown(() => AgentRun.checks = true);

  late List<String> prompts;

  AgentRun build({bool alternate = false}) {
    prompts = [];
    var n = 0;
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          final msgs = j['messages'] as List;
          prompts.add((msgs.last as Map)['content'].toString());
          // Le second modèle, lui, change d'approche.
          if (j['model'] == 'm2') return sse(done);
          // Alterné : deux recherches refaites tour à tour, jamais deux fois
          // de suite la même.
          return sse(alternate && (n++).isOdd ? other : same);
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

  test('recherches refaites en alternance : repérées, l\'agent est sommé de '
      'décider, puis la session s\'arrête avec une explication', () async {
    final run = build(alternate: true);
    await run.run();
    expect(run.running, isFalse);
    // Jamais deux fois de suite la même action : pas la boucle simple.
    expect(prompts.any((p) => p.contains('inutile de la répéter')), isFalse);
    expect(prompts.any((p) => p.contains('tu tournes en rond')), isTrue);
    expect(run.steps.last.text, contains('tourne en rond'));
    // Arrêté vite, pas après toutes les étapes permises.
    expect(prompts.length, lessThan(15));
  });

  test(
    'recherches refaites en alternance : un autre modèle prend la suite',
    () async {
      final run = build(alternate: true)
        ..fallback = (e, tried) async => tried.contains('groq::m2')
            ? null
            : (providersCatalog.firstWhere((p) => p.id == 'groq'), 'k', 'm2');
      await run.run();
      expect(run.model, 'm2');
      expect(run.summary, 'Fait autrement');
    },
  );

  test('une nouvelle recherche après une modification n\'est pas une boucle', () async {
    var n = 0;
    final edit =
        '```json\n{"tool": "write_file", "args": {"path": "a.rs", "content": "fn a() {}"}}\n```';
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final msgs =
              (jsonDecode(await body.bytesToString()) as Map)['messages']
                  as List;
          prompts.add((msgs.last as Map)['content'].toString());
          n++;
          // Recherche, modification, puis la même recherche (vérification).
          return sse(switch (n) {
            1 || 3 || 5 => same,
            2 => edit,
            4 => other,
            _ => done,
          });
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
      task: 'Ajoute la fonction a',
    );
    prompts = [];
    await run.run();
    expect(run.summary, 'Fait autrement');
    expect(prompts.any((p) => p.contains('tu tournes en rond')), isFalse);
  });
}
