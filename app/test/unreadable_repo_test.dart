import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// GitHub : le dépôt « api » refuse les [fails] premières lectures de sa liste
/// de fichiers, « site » répond toujours.
GitHubApi github({required int fails, Set<String> broken = const {}}) {
  var left = fails;
  return GitHubApi(
    't',
    client: MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/git/trees/')) {
        final repo = path.split('/')[3];
        if (broken.contains(repo) || (repo == 'api' && left-- > 0)) {
          return http.Response('{"message":"Bad credentials"}', 401);
        }
        return http.Response(
          jsonEncode({
            'tree': [
              {
                'path': repo == 'api' ? 'src/main.rs' : 'index.html',
                'type': 'blob',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{"message":"Not Found"}', 404);
    }),
  );
}

(LlmClient, List<String>) scripted(List<String> replies) {
  var i = 0;
  final seen = <String>[];
  return (
    LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        final sent = jsonDecode(await body.bytesToString()) as Map;
        seen.add(((sent['messages'] as List).last as Map)['content'] as String);
        final r = i < replies.length
            ? replies[i++]
            : '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
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
    ),
    seen,
  );
}

AgentRun runWith(
  LlmClient llm,
  GitHubApi gh, {
  List<RepoTarget> extra = const [],
}) => AgentRun(
  llm: llm,
  github: gh,
  provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
  apiKey: null,
  model: 'openai',
  owner: 'max',
  repo: 'api',
  branch: 'main',
  extraRepos: extra,
  task: 'Ajoute une route /sante',
)..specs.add('déjà compris');

void main() {
  AgentRun.checks = false;

  test('dépôt illisible : la session s\'arrête tout de suite en disant '
      'pourquoi, sans faire tourner le modèle', () async {
    final (llm, seen) = scripted(const []);
    final run = runWith(llm, github(fails: 99));
    await run.run();
    expect(seen, isEmpty);
    expect(run.running, isFalse);
    expect(run.steps.last.kind, StepKind.error);
    expect(
      run.steps.last.text,
      contains('Impossible de lire le dépôt max/api'),
    );
    expect(run.steps.last.text, contains('Bad credentials'));
    expect(run.status, SessionStatus.stopped);
    expect(run.history, isEmpty);
  });

  test('« continue » après un échec de lecture : la session repart', () async {
    final (llm, seen) = scripted(const []);
    final run = runWith(llm, github(fails: 1));
    await run.run();
    expect(seen, isEmpty);
    await run.run(followUp: 'continue');
    expect(seen.first, contains('src/main.rs'));
    expect(run.steps.last.kind, StepKind.done);
  });

  test('une lecture ratée de la liste des fichiers n\'est pas gardée : elle '
      'est redemandée ensuite', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"list_files","args":{}}\n```',
    ]);
    final run = runWith(
      llm,
      github(fails: 1),
      extra: const [RepoTarget('max', 'site', 'main')],
    );
    await run.run();
    // Au départ, seul « site » est lisible ; la session continue quand même.
    expect(seen.first, contains('site/index.html'));
    expect(seen.first, isNot(contains('src/main.rs')));
    // Le list_files suivant relit « api », qui répond cette fois.
    expect(seen[1], contains('api/src/main.rs'));
    expect(seen[1], isNot(contains('illisible')));
  });
}
