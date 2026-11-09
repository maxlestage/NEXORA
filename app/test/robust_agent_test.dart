import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Paquets a des fichiers ; galerie est vide (aucun commit : 409).
GitHubApi fake(List<String> calls) => GitHubApi(
  't',
  client: MockClient((req) async {
    final p = req.url.path;
    calls.add('${req.method} $p');
    if (p.contains('/galerie/')) {
      if (req.method == 'PUT' && p.contains('/contents/')) {
        return http.Response(
          jsonEncode({
            'content': {'sha': 'f1'},
          }),
          201,
        );
      }
      return http.Response('{"message":"Git Repository is empty."}', 409);
    }
    if (p.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'site/src/server/export.rs', 'type': 'blob'},
            {'path': 'site/Cargo.toml', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

LlmClient scripted(List<String> replies) {
  var i = 0;
  return LlmClient(
    clientFactory: () => MockClient.streaming((req, body) async {
      await body.drain<void>();
      final r = replies[i++];
      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': r},
                },
              ],
            })}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }),
  );
}

String act(Map j) => '```json\n${jsonEncode(j)}\n```';

void main() {
  test('un dépôt vide et un fichier absent ne sont plus des erreurs', () async {
    final calls = <String>[];
    final run = AgentRun(
      llm: scripted([
        act({
          'thought': 'Je regarde',
          'actions': [
            {
              'tool': 'list_files',
              'args': {'path': 'Paquets/site'},
            },
            {
              'tool': 'read_file',
              'args': {'path': 'Paquets/site/src/server.rs'},
            },
          ],
        }),
        act({
          'tool': 'finish',
          'args': {'summary': 'ok'},
        }),
      ]),
      github: fake(calls),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'galerie',
      branch: 'main',
      task: 'Galerie',
      extraRepos: const [RepoTarget('max', 'Paquets', 'master')],
    );
    await run.run();
    expect(run.steps.where((s) => s.kind == StepKind.error), isEmpty);
    final results = run.steps
        .where((s) => s.kind == StepKind.result)
        .map((s) => s.text)
        .join('\n');
    expect(results, contains('Paquets/site/Cargo.toml'));
    expect(results, contains('galerie est vide'));
    expect(results, contains('Fichier introuvable'));
    expect(results, contains('Paquets/site/src/server/export.rs'));
    // La liste du départ et la lecture se font en parallèle, sans erreur.
    expect(run.summary, 'ok');
  });

  test('premier commit dans un dépôt vide', () async {
    final calls = <String>[];
    final sha = await fake(calls).commitFiles(
      'max',
      'galerie',
      branch: 'main',
      message: 'Galerie',
      changes: [FileChange.write('index.html', '<canvas>')],
    );
    expect(sha, 'f1');
    expect(calls.last, 'PUT /repos/max/galerie/contents/index.html');
  });

  test('instruction pendant le travail : lue au tour suivant', () async {
    final run = AgentRun(
      llm: scripted([
        act({
          'tool': 'finish',
          'args': {'summary': 'ok'},
        }),
      ]),
      github: fake([]),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'Paquets',
      branch: 'master',
      task: 'Tâche',
    );
    run.steer('Utilise uniquement Paquets');
    await run.run();
    expect(
      run.history.any((m) => m.content.contains('Utilise uniquement Paquets')),
      isTrue,
    );
    expect(run.steps.first.kind, StepKind.user);
  });
}
