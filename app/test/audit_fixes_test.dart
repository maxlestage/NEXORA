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

String act(Map j) => '```json\n${jsonEncode(j)}\n```';

AgentRun agent(
  LlmClient llm,
  GitHubApi gh, {
  List<RepoTarget> extra = const [],
}) => AgentRun(
  llm: llm,
  github: gh,
  provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
  apiKey: 'k',
  model: 'm',
  owner: 'max',
  repo: 'a',
  branch: 'main',
  task: 'Tâche',
  extraRepos: extra,
);

GitHubApi github(List<String> calls) => GitHubApi(
  't',
  client: MockClient((req) async {
    final p = req.url.path;
    calls.add('${req.method} $p');
    Map body() => req.body.isEmpty ? {} : jsonDecode(req.body) as Map;
    if (p.contains('/git/trees/')) {
      return http.Response('{"tree":[]}', 200);
    }
    if (p.contains('/git/ref/heads/')) {
      return http.Response('{"object":{"sha":"p0"}}', 200);
    }
    if (p.contains('/git/commits/')) {
      return http.Response('{"tree":{"sha":"t0"}}', 200);
    }
    if (p.endsWith('/git/trees')) return http.Response('{"sha":"t1"}', 201);
    if (p.endsWith('/git/commits')) {
      return http.Response('{"sha":"c123456789"}', 201);
    }
    if (p.contains('/git/refs')) return http.Response('{}', 201);
    if (p.endsWith('/pulls')) {
      return http.Response(
        jsonEncode({
          'number': 1,
          'title': 't',
          'html_url': 'https://github.com${p.replaceAll('/repos', '')}/1',
          'state': 'open',
          'user': {'login': 'max'},
          'head': body()['head'],
        }),
        201,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

void main() {
  test('écritures simultanées : aucun fichier abîmé, rien de perdu', () async {
    final dir = await Directory.systemTemp.createTemp('nexora');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileConversationStore(dir);
    final all = [
      for (var i = 0; i < 30; i++) Conversation(id: 'c$i', title: 'T$i'),
    ];
    await Future.wait([
      for (var i = 0; i < 30; i++) store.saveIndex(all.sublist(0, i + 1)),
      for (final c in all) store.save(c),
    ]);
    expect(await store.loadIndex(), hasLength(30));
  });

  test(
    'Arrêter : l\'agent s\'arrête tout de suite, sans attendre le modèle',
    () async {
      final never = Completer<http.StreamedResponse>();
      final run = agent(
        LlmClient(
          clientFactory: () => MockClient.streaming((r, b) => never.future),
        ),
        github([]),
      );
      final done = run.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(run.running, isTrue);
      run.stop();
      await done.timeout(const Duration(seconds: 2));
      expect(run.running, isFalse);
      expect(run.steps.last.text, 'Arrêté.');
    },
  );

  test('une instruction pendant le dernier tour relance le travail', () async {
    final gate = Completer<void>();
    var calls = 0;
    late AgentRun run;
    run = agent(
      LlmClient(
        clientFactory: () => MockClient.streaming((r, b) async {
          await b.drain<void>();
          calls++;
          if (calls == 1) {
            run.steer('Ajoute un README');
            await gate.future;
          }
          return sse(
            act({
              'tool': 'finish',
              'args': {'summary': 'fini $calls'},
            }),
          );
        }),
      ),
      github([]),
    );
    final done = run.run();
    gate.complete();
    await done;
    expect(calls, 2);
    expect(run.summary, 'fini 2');
    expect(
      run.history.where((m) => m.content.contains('Ajoute un README')),
      hasLength(1),
    );
  });

  test('plusieurs dépôts : un dépôt sans pull request n\'est jamais envoyé en direct', () async {
    final calls = <String>[];
    final run = agent(
      LlmClient(),
      github(calls),
      extra: const [RepoTarget('max', 'b', 'main')],
    );
    run.pulls['max/a'] = 'https://github.com/max/a/pull/1';
    run.heads['max/a'] = 'nexora/x';
    run.changes['b/README.md'] = 'B\n';
    final results = await run.commitAll(
      message: 'm',
      targetBranch: 'nexora/y',
      openPr: true,
    );
    expect(results.single.isPull, isTrue);
    expect(calls, contains('PATCH /repos/max/b/git/refs/heads/nexora/y'));
    expect(calls, isNot(contains('PATCH /repos/max/b/git/refs/heads/main')));
    expect(run.pulls.keys, containsAll(['max/a', 'max/b']));
    expect(run.changes, isEmpty);
  });
}
