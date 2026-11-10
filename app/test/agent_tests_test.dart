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

String act(String tool, Map args, [String? content]) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```\n$content\n```'}';

void main() {
  late List<String> requests;

  AgentRun build(List<String> replies, {http.Client? gh}) {
    var i = 0;
    requests = [];
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          requests.add(await body.bytesToString());
          return sse(replies[i++]);
        }),
      ),
      github: GitHubApi(
        't',
        client:
            gh ?? MockClient((_) async => http.Response('{"tree":[]}', 200)),
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

  test(
    'du code sans test : l\'agent est renvoyé écrire les tests, puis relit',
    () async {
      final run = build([
        act('write_file', {
          'path': 'lib/somme.dart',
        }, 'int somme(a, b) => a + b;'),
        act('finish', {'summary': 'Fait'}),
        // Renvoyé écrire les tests.
        act('write_file', {
          'path': 'test/somme_test.dart',
        }, 'void main() { expect(somme(1, 2), 3); }'),
        act('finish', {'summary': 'Fait, avec tests'}),
        // Relecture finale : tout est bon.
        act('finish', {'summary': 'Fait, avec tests, relu'}),
      ]);
      await run.run();
      expect(run.summary, 'Fait, avec tests, relu');
      expect(run.changes.keys, contains('test/somme_test.dart'));
      expect(requests[2], contains('sans écrire de test'));
      // La relecture montre le diff de chaque fichier.
      expect(requests[4], contains('relis TOUTES tes modifications'));
      expect(requests[4], contains('### lib/somme.dart'));
      expect(requests[4], contains('+1: int somme(a, b) => a + b;'));
    },
  );

  test('fichiers de tests reconnus', () {
    for (final p in [
      'test/a_test.dart',
      'src/a.test.ts',
      'tests/test_a.py',
      'e2e/largeur.spec.js',
      '.github/workflows/ci.yml',
      'crates/x/tests/it.rs',
    ]) {
      expect(AgentRun.isTestFile(p), isTrue, reason: p);
    }
    expect(AgentRun.isTestFile('src/main.rs'), isFalse);
    expect(AgentRun.isTestFile('site/style.css'), isFalse);
  });

  test('tests GitHub : échec → rapport avec la fin du journal', () async {
    final run = build(
      [],
      gh: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/commits/abc123/check-runs')) {
          return http.Response(
            jsonEncode({
              'check_runs': [
                {
                  'id': 7,
                  'name': 'tests',
                  'status': 'completed',
                  'conclusion': 'failure',
                  'html_url': 'https://github.com/max/site/actions/runs/1',
                },
                {
                  'id': 8,
                  'name': 'lint',
                  'status': 'completed',
                  'conclusion': 'success',
                },
              ],
            }),
            200,
          );
        }
        if (p.endsWith('/actions/jobs/7/logs')) {
          return http.Response(
            '2026-11-10T07:00:00.000Z Running tests\n'
            '2026-11-10T07:00:01.000Z FAIL somme: expected 3, got 4',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    run.commits.add('max/site@abc123');
    final report = await run.watchCi(every: Duration.zero);
    expect(run.ci['max/site']!.state, CiState.failed);
    expect(report, contains('tests : failure'));
    expect(report, contains('FAIL somme: expected 3, got 4'));
    expect(report, isNot(contains('2026-11-10T')));
  });

  test('tests GitHub : tout passe → pas de rapport', () async {
    final run = build(
      [],
      gh: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'check_runs': [
              {
                'id': 1,
                'name': 'tests',
                'status': 'completed',
                'conclusion': 'success',
              },
            ],
          }),
          200,
        ),
      ),
    );
    run.commits.add('max/site@def456');
    expect(await run.watchCi(every: Duration.zero), isNull);
    expect(run.ci['max/site']!.state, CiState.passed);
    expect(run.ci['max/site']!.label, contains('réussis'));
  });

  test('pas de tests sur GitHub : signalé, sans rapport', () async {
    final run = build(
      [],
      gh: MockClient(
        (_) async => http.Response(jsonEncode({'check_runs': []}), 200),
      ),
    );
    run.commits.add('max/site@0aa');
    expect(
      await run.watchCi(every: Duration.zero, noneAfter: Duration.zero),
      isNull,
    );
    expect(run.ci['max/site']!.state, CiState.none);
  });
}
