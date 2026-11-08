import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/session_store.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/agent_state.dart';
import 'package:nexora/state/github_state.dart';
import 'package:nexora/state/session_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderDef P(String id) => providersCatalog.firstWhere((p) => p.id == id);

/// Un faux GitHub qui note les branches écrites et les pull requests ouvertes.
class FakeGitHub {
  final pulls = <String>[];
  final pushedTo = <String>[];

  GitHubApi get api => GitHubApi(
    't',
    client: MockClient((req) async {
      final p = req.url.path;
      Map body() => req.body.isEmpty ? {} : jsonDecode(req.body) as Map;
      if (p.contains('/git/trees/') && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'tree': [
              {'path': 'README.md', 'type': 'blob'},
            ],
          }),
          200,
        );
      }
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
        return http.Response(jsonEncode({'sha': 'c1234567890'}), 201);
      }
      if (p.contains('/git/refs/heads/') && req.method == 'PATCH') {
        pushedTo.add(p.split('/git/refs/heads/').last);
        return http.Response('{}', 200);
      }
      if (p.endsWith('/git/refs')) {
        return http.Response(jsonEncode({'ref': body()['ref']}), 201);
      }
      if (p.endsWith('/pulls')) {
        pulls.add(body()['head'] as String);
        return http.Response(
          jsonEncode({
            'number': pulls.length,
            'title': body()['title'],
            'html_url': 'https://github.com/max/galerie/pull/${pulls.length}',
            'state': 'open',
            'user': {'login': 'max'},
          }),
          201,
        );
      }
      return http.Response('{"message":"Not Found"}', 404);
    }),
  );
}

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

String act(String tool, Map args, [String? content]) =>
    '```json\n${jsonEncode({'thought': '…', 'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```\n$content\n```'}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session : suite d\'instructions et même pull request', () async {
    final gh = FakeGitHub();
    final run = AgentRun(
      llm: scripted([
        act('write_file', {'path': 'galerie/index.html'}, '<canvas>'),
        act('finish', {'summary': 'Galerie', 'commit_message': 'Galerie 3D'}),
        act('write_file', {'path': 'galerie/style.css'}, 'body{}'),
        act('finish', {'summary': 'Style'}),
      ]),
      github: gh.api,
      provider: P('groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'galerie',
      branch: 'main',
      task: 'Galerie 3D',
      extraRepos: const [RepoTarget('max', 'paquets', 'master')],
    );
    await run.run();
    expect(run.status, SessionStatus.review);
    expect(run.reposLabel, 'galerie, +1 autre');
    expect(run.stats, (1, 0));

    final first = await run.commitAll(
      message: 'Galerie 3D',
      targetBranch: 'nexora/galerie',
      openPr: true,
    );
    expect(first.single.isPull, isTrue);
    expect(run.status, SessionStatus.shipped);
    expect(run.heads, {'max/galerie': 'nexora/galerie'});
    expect(run.changes, isEmpty);

    // Nouvelle instruction : l'historique continue.
    await run.run(followUp: 'Ajoute une feuille de style');
    expect(run.steps.any((s) => s.kind == StepKind.user), isTrue);
    expect(
      run.history.where((m) => m.content.contains('feuille')),
      hasLength(1),
    );
    expect(run.changes.keys, ['galerie/style.css']);

    // Second envoi : sur la même branche, sans nouvelle pull request.
    final second = await run.commitAll(message: 'Style');
    expect(second.single.result, first.single.result);
    expect(gh.pulls, ['nexora/galerie']);
    expect(gh.pushedTo, ['nexora/galerie', 'nexora/galerie']);
  });

  test('session enregistrée puis rechargée', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final store = PrefsSessionStore(storage);
    final run = AgentRun(
      llm: LlmClient(),
      github: GitHubApi(null),
      provider: P('groq'),
      apiKey: null,
      model: 'llama-3.3-70b-versatile',
      owner: 'max',
      repo: 'galerie',
      branch: 'main',
      task: 'Galerie 3D',
      extraRepos: const [RepoTarget('max', 'paquets', 'master')],
    );
    run.steps.add(AgentStep(StepKind.thought, 'Je regarde'));
    run.history.add(const LlmMessage('user', 'Tâche'));
    run.changes['galerie/a.txt'] = 'A\n';
    run.originals['galerie/a.txt'] = null;
    run.pulls['max/galerie'] = 'https://github.com/max/galerie/pull/1';
    run.running = true; // l'app est fermée pendant le travail
    await store.save(run.id, run.toJson());

    final settings = SettingsState(storage, LlmClient());
    final sessions = SessionState(
      storage: storage,
      settings: settings,
      github: GitHubState(storage),
      agents: AgentState(storage),
      llm: LlmClient(),
      store: store,
    );
    await sessions.ready;
    final back = sessions.sessions.single;
    expect(back.id, run.id);
    expect(back.targets.map((t) => t.fullName), ['max/galerie', 'max/paquets']);
    expect(back.changes, {'galerie/a.txt': 'A\n'});
    expect(back.steps.single.text, 'Je regarde');
    expect(back.history.single.content, 'Tâche');
    expect(back.pulls.values.single, contains('/pull/1'));
    expect(back.interrupted, isTrue);
    expect(back.status, SessionStatus.review);

    sessions.delete(back.id);
    await Future<void>.delayed(Duration.zero);
    expect(await store.loadAll(), isEmpty);
  });
}
