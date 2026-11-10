import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

import 'self_heal_test.dart' show FakeHub, build;

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

void main() {
  GitHubApi.retryPause = Duration.zero;

  test('un brouillon modifié pendant l\'envoi reste un brouillon', () async {
    final hub = FakeHub();
    late AgentRun run;
    final api = hub.api;
    // Pendant l'envoi, l'agent modifie encore le fichier.
    run = AgentRun(
      llm: LlmClient(),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.endsWith('/git/commits') && req.method == 'POST') {
            run.changes['a.css'] = 'v2\n';
          }
          final r = await api.raw(
            req.method,
            req.url.path,
            body: req.body.isEmpty ? null : jsonDecode(req.body),
          );
          return http.Response(r.$2, r.$1);
        }),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 't',
    );
    run.changes['a.css'] = 'v1\n';
    await run.commitAll(message: 'm', targetBranch: 'nexora/x', openPr: true);
    expect(run.changes['a.css'], 'v2\n'); // pas perdu
    expect(run.originals['a.css'], 'v1\n'); // ce qui est vraiment parti
  });

  test(
    'ce qui a été envoyé est gardé avec la session (conflit après relance)',
    () {
      final run = build(FakeHub());
      run.bases['a.css'] = 'base\n';
      run.originals['a.css'] = 'envoyé\n';
      final j = jsonDecode(jsonEncode(run.toJson())) as Map;
      expect((j['originals'] as Map)['a.css'], 'envoyé\n');
    },
  );

  test('outil github : pas de contournement par « .. » ni par /merges', () {
    final run = build(FakeHub());
    for (final p in [
      '/repos/max/site/x/../pulls/1/merge',
      '/repos/max/site/x/%2e%2e/pulls/1/merge',
      '/repos/max/site/x/..',
      '/repos/max/site/x/../../autre',
    ]) {
      expect(run.githubDenied('PUT', p), isNotNull, reason: p);
      expect(run.githubDenied('GET', p), isNotNull, reason: p);
    }
    expect(run.githubDenied('POST', '/repos/max/site/merges'), isNotNull);
    expect(
      run.githubDenied('POST', '/repos/max/site/branches/main/rename'),
      isNotNull,
    );
  });

  test('après une fusion, les copies du dépôt sont oubliées', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.changes['a.css'] = 'x\n';
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(run.merged, hasLength(1));
    expect(run.bases, isEmpty);
    expect(run.originals.containsKey('a.css'), isFalse);
  });

  test('un fichier qui contient des blocs ``` reste entier dans ````', () {
    const reply =
        '```json\n{"tool":"write_file","args":{"path":"README.md"}}\n```\n'
        '````markdown\n# Titre\n\n```sh\ncargo run\n```\n\nFin.\n````';
    final c = parseToolCalls(reply).single;
    expect(c.args['content'], '# Titre\n\n```sh\ncargo run\n```\n\nFin.\n');
    // Fins de ligne CRLF.
    final crlf = parseToolCalls(
      '```json\r\n{"tool":"write_file","args":{"path":"a"}}\r\n```\r\n'
      '```\r\nA\r\n```',
    ).single;
    expect(crlf.args['content'], 'A\n');
  });

  test(
    'un rapport de CI de l\'app n\'est pas une demande de l\'utilisateur',
    () async {
      final run = AgentRun(
        llm: LlmClient(
          clientFactory: () => MockClient.streaming(
            (req, body) async => sse(
              '```json\n{"tool":"finish","args":{"summary":"corrigé"}}\n```',
            ),
          ),
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
        task: 'Titre en bleu',
      );
      run.history.add(const LlmMessage('user', 'Tâche : Titre en bleu'));
      run.history.add(const LlmMessage('assistant', 'ok'));
      await run.run(followUp: 'Les tests GitHub ont échoué…', fromApp: true);
      expect(run.requests, ['Titre en bleu']);
      expect(run.steps.where((s) => s.kind == StepKind.user), isEmpty);
      // Arrêté par l'utilisateur : l'app ne relance plus rien.
      run.stop();
      final before = run.steps.length;
      await run.run(followUp: 'Encore un rapport', fromApp: true);
      expect(run.steps.length, before);
      expect(await run.watchCi(), isNull);
    },
  );

  test(
    'une vérification annulée ou en attente d\'action n\'est pas réussie',
    () {
      CheckRun r(String c) =>
          CheckRun(id: 1, name: 'x', status: 'completed', conclusion: c);
      expect(r('cancelled').failed, isTrue);
      expect(r('action_required').failed, isTrue);
      expect(r('success').failed, isFalse);
      expect(r('skipped').failed, isFalse);
    },
  );
}
