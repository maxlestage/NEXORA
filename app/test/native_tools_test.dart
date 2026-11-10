import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

String chunk(Map delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': ?finish},
      ],
    })}\n\n';

/// Une réponse où le modèle appelle l'outil par le canal natif `tool_calls`
/// (comme gpt-oss, GPT, Qwen…), sans écrire de texte.
http.StreamedResponse nativeCall(String name, Map args) {
  final a = jsonEncode(args);
  final half = a.length ~/ 2;
  return http.StreamedResponse(
    Stream.fromIterable(
      [
        chunk({'role': 'assistant', 'content': ''}),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'c1',
              'type': 'function',
              'function': {'name': name, 'arguments': ''},
            },
          ],
        }),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': a.substring(0, half)},
            },
          ],
        }),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': a.substring(half)},
            },
          ],
        }, finish: 'tool_calls'),
        'data: [DONE]\n\n',
      ].map(utf8.encode),
    ),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse text(String t) => http.StreamedResponse(
  Stream.fromIterable(
    [
      chunk({'content': t}),
      'data: [DONE]\n\n',
    ].map(utf8.encode),
  ),
  200,
  headers: {'content-type': 'text/event-stream'},
);

String act(String tool, Map args) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```';

void main() {
  // Les tests obligatoires et la relecture finale ont leurs propres tests.
  AgentRun.checks = false;
  const readme = '# Projet\n\nUn projet.\n';

  AgentRun build(
    List<http.StreamedResponse Function()> replies, {
    int max = 24,
  }) {
    var i = 0;
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          await body.drain<void>();
          return replies[i++]();
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  {'path': 'README.md', 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          if (req.url.path.endsWith('/contents/README.md')) {
            return http.Response(
              jsonEncode({
                'sha': 's',
                'content': base64.encode(utf8.encode(readme)),
                'encoding': 'base64',
              }),
              200,
            );
          }
          return http.Response('{"message":"Not Found"}', 404);
        }),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
      apiKey: null,
      model: 'openai-fast',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Ajoute une section Contribuer à la fin du README',
      maxSteps: max,
    );
  }

  test('les appels d\'outils natifs (tool_calls) sont compris', () async {
    final run = build([
      () => nativeCall('read_file', {'path': 'README.md'}),
      () => nativeCall('edit_file', {
        'path': 'README.md',
        'old_string': '',
        'new_string': '## Contribuer\n\nBienvenue.',
      }),
      () => nativeCall('finish', {'summary': 'Section ajoutée'}),
    ]);
    await run.run();
    expect(run.summary, 'Section ajoutée');
    expect(run.changes['README.md'], contains('## Contribuer'));
    expect(run.changes['README.md'], startsWith('# Projet'));
  });

  test(
    'un seul bloc pour edit_file : ajout à la fin, une seule fois',
    () async {
      final once =
          '```json\n${jsonEncode({
            'tool': 'edit_file',
            'args': {'path': 'README.md'},
          })}\n```\n```\n## Contribuer\n```';
      final run = build([
        () => text(once),
        () => text(once),
        () => text(act('finish', {'summary': 'ok'})),
      ]);
      await run.run();
      final after = run.changes['README.md']!;
      expect('## Contribuer'.allMatches(after), hasLength(1));
      expect(run.summary, 'ok');
    },
  );

  test('autres écritures d\'une action : {"finish": …} et {"name": …}', () {
    expect(
      parseToolCalls('{"thought":"x","finish":{"summary":"fait"}}').single.tool,
      'finish',
    );
    final c = parseToolCalls(
      '{"name":"read_file","arguments":"{\\"path\\":\\"a.md\\"}"}',
    ).single;
    expect(c.tool, 'read_file');
    expect(c.args['path'], 'a.md');
    expect(
      parseToolCalls('```json\n{"summary":"fini"}\n```').single.tool,
      'finish',
    );
  });

  test('une boucle sur la même action est arrêtée', () async {
    final read = act('read_file', {'path': 'README.md'});
    final run = build([
      () => text(read),
      () => text(read),
      () => text(read),
      () => text(read),
      () => text(read),
    ]);
    await run.run();
    expect(run.steps.last.kind, StepKind.error);
    expect(run.steps.last.text, contains('en boucle'));
  });

  test('réponses vides : redemandées, puis message clair', () async {
    final run = build([() => text(''), () => text(''), () => text('')]);
    await run.run();
    expect(run.steps.last.text, contains('réponse vide'));
    expect(run.history.where((m) => m.role == 'assistant'), isEmpty);
  });

  test(
    'limite d\'étapes : l\'agent fait le point et continue jusqu\'au bout',
    () async {
      final run = build([
        () => text(act('read_file', {'path': 'README.md', 'start': 1})),
        () => text(act('read_file', {'path': 'README.md', 'start': 2})),
        // Après le point : il continue et termine.
        () => text(act('read_file', {'path': 'README.md', 'start': 3})),
        () => text(act('finish', {'summary': 'Fini après le point'})),
      ], max: 2);
      await run.run();
      expect(run.summary, 'Fini après le point');
      expect(
        run.steps.any(
          (s) => s.text.contains('je fais le point et je continue'),
        ),
        isTrue,
      );
    },
  );

  test('modèle qui ne répond plus : l\'agent continue avec un autre', () async {
    var calls = 0;
    final run =
        AgentRun(
            llm: LlmClient(
              clientFactory: () => MockClient.streaming((req, body) async {
                await body.drain<void>();
                calls++;
                if (req.url.host.contains('groq')) {
                  return http.StreamedResponse(
                    Stream.value(
                      utf8.encode('{"error":{"message":"Invalid API Key"}}'),
                    ),
                    401,
                  );
                }
                return text(
                  act('finish', {'summary': 'Fini avec Pollinations'}),
                );
              }),
            ),
            github: GitHubApi(
              't',
              client: MockClient(
                (_) async => http.Response('{"tree":[]}', 200),
              ),
            ),
            provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
            apiKey: 'mauvaise',
            model: 'm',
            owner: 'max',
            repo: 'site',
            branch: 'main',
            task: 'Dis bonjour',
          )
          ..fallback = (e, tried) async =>
              tried.contains('pollinations::openai')
              ? null
              : (
                  providersCatalog.firstWhere((p) => p.id == 'pollinations'),
                  null,
                  'openai',
                );
    await run.run();
    expect(run.summary, 'Fini avec Pollinations');
    expect(run.provider.id, 'pollinations');
    expect(run.steps.any((s) => s.text.contains('Je continue avec')), isTrue);
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('noms d\'outils inventés ramenés aux vrais', () {
    expect(canonicalTool('repo_browser.search_code'), 'search_code');
    expect(canonicalTool('functions.read_file'), 'read_file');
    expect(canonicalTool('Grep'), 'search_code');
    expect(canonicalTool('str_replace'), 'edit_file');
    final c = parseToolCalls(
      '{"tool":"repo_browser.edit_file","args":{"path":"a"}}',
    ).single;
    expect(c.tool, 'edit_file');
  });

  test('search_code cherche dans le contenu, avec le code autour', () async {
    final run = build([
      () => text(act('search_code', {'query': 'un projet'})),
      () => text(act('finish', {'summary': 'ok'})),
    ]);
    await run.run();
    final result = run.history
        .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
        .content;
    expect(result, contains('README.md'));
    expect(result, contains('>3: Un projet.'));
  });

  test(
    'conversation trop longue : historique allégé, l\'agent continue',
    () async {
      var calls = 0;
      final run = build([
        () {
          calls++;
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                '{"error":{"message":"This model\'s maximum context length is 8192 tokens"}}',
              ),
            ),
            400,
          );
        },
        () => text(act('read_file', {'path': 'README.md'})),
        () => text(act('finish', {'summary': 'ok'})),
      ]);
      await run.run();
      expect(calls, 1);
      expect(run.summary, 'ok');
      expect(
        run.steps.any((s) => s.text.contains('historique allégé')),
        isTrue,
      );
    },
  );
}
