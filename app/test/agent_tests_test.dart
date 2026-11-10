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
        // Renvoyé écrire le workflow GitHub.
        act('write_file', {
          'path': '.github/workflows/ci.yml',
        }, 'on: [push, pull_request]'),
        act('finish', {'summary': 'Fait, avec CI'}),
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
      expect(run.changes.keys, contains('.github/workflows/ci.yml'));
      expect(requests[2], contains('Aucun workflow GitHub'));
      expect(requests[4], contains('sans écrire de test'));
      // La relecture montre le diff de chaque fichier.
      expect(requests[6], contains('relis TOUTES tes modifications'));
      expect(requests[6], contains('### lib/somme.dart'));
      expect(requests[6], contains('+1: int somme(a, b) => a + b;'));
    },
  );

  test('fichiers de tests reconnus', () {
    for (final p in [
      'test/a_test.dart',
      'src/a.test.ts',
      'tests/test_a.py',
      'e2e/largeur.spec.js',
      'crates/x/tests/it.rs',
    ]) {
      expect(AgentRun.isTestFile(p), isTrue, reason: p);
    }
    expect(AgentRun.isTestFile('src/main.rs'), isFalse);
    expect(AgentRun.isTestFile('site/style.css'), isFalse);
    expect(AgentRun.isTestFile('.github/workflows/ci.yml'), isFalse);
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

  test('boucle CI : envoi sur une branche avec pull request, échec puis vert', () async {
    var round = 0;
    final pushed = <String>[];
    final pulls = <String>[];
    final gh = MockClient((req) async {
      final p = req.url.path;
      Map body() => req.body.isEmpty ? {} : jsonDecode(req.body) as Map;
      if (p.contains('/git/ref/heads/')) {
        return http.Response(
          jsonEncode({
            'object': {'sha': 'p0'},
          }),
          200,
        );
      }
      if (p.contains('/git/commits/') && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'tree': {'sha': 't0'},
          }),
          200,
        );
      }
      if (p.endsWith('/git/trees')) {
        return http.Response(jsonEncode({'sha': 't1'}), 201);
      }
      if (p.endsWith('/git/commits')) {
        round++;
        return http.Response(jsonEncode({'sha': 'c$round'}), 201);
      }
      if (p.contains('/git/refs/heads/') && req.method == 'PATCH') {
        pushed.add(p.split('/git/refs/heads/').last);
        return http.Response('{}', 200);
      }
      if (p.endsWith('/git/refs')) {
        return http.Response(jsonEncode({'ref': body()['ref']}), 201);
      }
      if (p.endsWith('/pulls')) {
        pulls.add(body()['head'] as String);
        return http.Response(
          jsonEncode({
            'number': 1,
            'title': 't',
            'html_url': 'https://github.com/max/site/pull/1',
            'state': 'open',
            'user': {'login': 'max'},
          }),
          201,
        );
      }
      if (p.contains('/check-runs')) {
        // Premier envoi : les tests échouent ; second : tout passe.
        final ok = p.contains('/commits/c2/');
        return http.Response(
          jsonEncode({
            'check_runs': [
              {
                'id': 9,
                'name': 'tests',
                'status': 'completed',
                'conclusion': ok ? 'success' : 'failure',
              },
            ],
          }),
          200,
        );
      }
      if (p.endsWith('/actions/jobs/9/logs')) {
        return http.Response('Error: somme(1, 2) vaut 4', 200);
      }
      if (p.contains('/git/trees/')) {
        return http.Response('{"tree":[]}', 200);
      }
      return http.Response('{"message":"Not Found"}', 404);
    });
    final run = build([], gh: gh);
    run.changes['lib/somme.dart'] = 'int somme(a, b) => a + b + 1;\n';
    run.commitMessage = 'Somme';

    final report = await run.shipForCi(every: Duration.zero);
    expect(report, contains('Error: somme(1, 2) vaut 4'));
    expect(run.ciNote, contains('l\'agent corrige'));
    expect(pulls, hasLength(1));
    final branch = pulls.single;
    expect(branch, startsWith('nexora/'));
    expect(pushed, [branch]); // jamais la branche principale

    // L'agent a corrigé : second envoi, sur la même branche, sans nouvelle PR.
    run.changes['lib/somme.dart'] = 'int somme(a, b) => a + b;\n';
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(run.ciNote, contains('entièrement verte'));
    expect(pushed, [branch, branch]);
    expect(pulls, hasLength(1));
    expect(run.ciRounds, 2);
  });
}
