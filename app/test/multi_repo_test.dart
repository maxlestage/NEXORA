import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

ProviderDef P(String id) => providersCatalog.firstWhere((p) => p.id == id);

/// Un faux GitHub avec deux dépôts.
GitHubApi fakeGitHub() => GitHubApi(
  't',
  client: MockClient((req) async {
    final p = req.url.path;
    if (p.contains('/git/trees/')) {
      final files = p.contains('/paquets/')
          ? ['Cargo.toml', 'src/lib.rs']
          : ['README.md'];
      return http.Response(
        jsonEncode({
          'tree': [
            for (final f in files) {'path': f, 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (p.endsWith('/contents/src/lib.rs')) {
      return http.Response(
        jsonEncode({
          'sha': 'abc',
          'content': base64.encode(utf8.encode('pub fn island() {}')),
          'encoding': 'base64',
          'size': 17,
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

AgentRun multiRun(LlmClient llm) => AgentRun(
  llm: llm,
  github: fakeGitHub(),
  provider: P('groq'),
  apiKey: 'k',
  model: 'm',
  owner: 'max',
  repo: 'galerie',
  branch: 'main',
  task: 'Galerie 3D avec Paquets',
  extraRepos: const [RepoTarget('max', 'paquets', 'master')],
)..retryPause = Duration.zero;

/// Un modèle qui joue une suite de réponses, une par appel.
LlmClient scripted(List<Object> replies) {
  var i = 0;
  return LlmClient(
    clientFactory: () => MockClient.streaming((req, body) async {
      await body.drain<void>();
      final r = replies[i++];
      if (r is int) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"overloaded"}}')),
          r,
        );
      }
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
    retryDelay: (_, _) => Duration.zero,
  );
}

String act(String tool, Map args, [String? content]) =>
    '```json\n${jsonEncode({'thought': '…', 'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```html\n$content\n```'}';

void main() {
  test('plusieurs dépôts : un dossier par dépôt', () async {
    final run = multiRun(LlmClient());
    expect(run.multi, isTrue);
    expect(run.resolve('paquets/src/lib.rs')!.$1.name, 'paquets');
    expect(run.resolve('paquets/src/lib.rs')!.$2, 'src/lib.rs');
    expect(run.resolve('README.md'), isNull);
  });

  test('mission : lit un dépôt, écrit dans l\'autre', () async {
    final run = multiRun(
      scripted([
        act('list_files', {}),
        act('read_file', {'path': 'paquets/src/lib.rs'}),
        act('write_file', {'path': 'index.html'}, '<p>raté</p>'),
        act('write_file', {'path': 'galerie/index.html'}, '<canvas></canvas>'),
        act('finish', {'summary': 'Fait', 'commit_message': 'Galerie 3D'}),
      ]),
    );
    await run.run();
    final results = run.steps
        .where((s) => s.kind == StepKind.result)
        .map((s) => s.text)
        .toList();
    expect(results.first, contains('paquets/Cargo.toml'));
    expect(results.first, contains('galerie/README.md'));
    expect(results[1], 'pub fn island() {}');
    // Sans dossier de dépôt : refusé, l'agent se corrige.
    expect(run.changes.keys, ['galerie/index.html']);
    expect(run.acceptedByRepo.keys.single.name, 'galerie');
    expect(run.acceptedByRepo.values.single.keys, ['index.html']);
    expect(run.summary, 'Fait');
  });

  test('une coupure ne termine plus la mission : nouvel essai', () async {
    // 503 trois fois de suite = échec du client (2 essais) puis l'agent réessaie.
    final run = multiRun(
      scripted([
        503,
        503,
        503,
        act('finish', {'summary': 'OK après coupure'}),
      ]),
    );
    await run.run();
    expect(run.summary, 'OK après coupure');
    expect(run.steps.any((s) => s.text.contains('Nouvel essai')), isTrue);
  });

  test(
    'fin annoncée : le flux se termine sans attendre la connexion',
    () async {
      final client = MockClient.streaming((req, body) async {
        final open = StreamController<List<int>>();
        open
          ..add(
            utf8.encode('data: {"choices":[{"delta":{"content":"Fini"}}]}\n\n'),
          )
          ..add(utf8.encode('data: [DONE]\n\n'));
        // La connexion reste ouverte : seul [DONE] indique la fin.
        return http.StreamedResponse(
          open.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final out =
          await LlmClient(
                clientFactory: () => client,
                idleTimeout: const Duration(seconds: 30),
              )
              .complete(
                provider: P('groq'),
                apiKey: 'k',
                model: 'm',
                messages: const [LlmMessage('user', 'a')],
              )
              .timeout(const Duration(seconds: 5));
      expect(out, 'Fini');
    },
  );

  test('erreurs à réessayer', () {
    expect(LlmException('x', status: 529).retryable, isTrue);
    expect(LlmException('x', transient: true).retryable, isTrue);
    expect(LlmException('clé invalide', status: 401).retryable, isFalse);
  });
}
