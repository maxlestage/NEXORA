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
import 'package:nexora/state/usage_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const finish = '```json\n{"tool": "finish", "args": {"summary": "Fait"}}\n```';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AgentRun.checks = false);
  tearDown(() => AgentRun.checks = true);

  final groq = providersCatalog.firstWhere((p) => p.id == 'groq');
  final openrouter = providersCatalog.firstWhere((p) => p.id == 'openrouter');

  late List<String> usage;
  late List<String> errors;
  late List<String> headers;

  /// Groq n'a plus de crédit (402) ; OpenRouter répond.
  AgentRun build() {
    usage = [];
    errors = [];
    headers = [];
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          await body.drain<void>();
          if (req.url.host == 'api.groq.com') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"error":{"message":"no credit"}}')),
              402,
              headers: {'x-ratelimit-remaining-requests': '0'},
            );
          }
          return sse(finish);
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
      ),
      provider: groq,
      apiKey: 'k',
      model: 'llama',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Ajoute une page contact',
      onUsage: (p, m, t) => usage.add('${p.id}::$m'),
      onError: (p, e) => errors.add(p.id),
      onHeaders: (p, h) => headers.add(p.id),
    );
  }

  test('après la bascule sur un autre modèle, les dépenses vont au modèle qui '
      'a vraiment répondu, l\'erreur à celui qui a échoué', () async {
    final run = build()
      ..fallback = (e, tried) async =>
          tried.contains('openrouter::gpt') ? null : (openrouter, 'k2', 'gpt');
    await run.run();
    expect(run.summary, 'Fait');
    expect(run.provider.id, 'openrouter');
    expect(errors, ['groq']);
    expect(usage, isNotEmpty);
    expect(usage.toSet(), {'openrouter::gpt'});
  });

  test('un modèle changé pendant la session (Réglages de la session) reçoit '
      'les dépenses de la suite', () async {
    final run = build()
      ..provider = openrouter
      ..apiKey = 'k2'
      ..model = 'gpt';
    await run.run();
    expect(run.summary, 'Fait');
    expect(errors, isEmpty);
    expect(usage.toSet(), {'openrouter::gpt'});
  });

  test('témoin de crédit : une session passée à un autre modèle compte la '
      'suite chez ce fournisseur, pas chez celui de départ', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final store = PrefsSessionStore(storage);
    final saved = AgentRun(
      llm: LlmClient(),
      github: GitHubApi(null),
      provider: groq,
      apiKey: null,
      model: 'llama-3.3-70b-versatile',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Ajoute une page contact',
    );
    await store.save(saved.id, saved.toJson());
    final hosts = <String>[];
    final llm = LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        await body.drain<void>();
        hosts.add(req.url.host);
        return sse(finish);
      }),
    );
    final usageState = UsageState(storage);
    final sessions = SessionState(
      storage: storage,
      settings: SettingsState(storage, LlmClient()),
      github: _FakeGitHub(storage),
      agents: AgentState(storage),
      llm: llm,
      usage: usageState,
      store: store,
    );
    await sessions.ready;
    final run = sessions.sessions.single;
    sessions.setModel(
      run,
      const ModelRef('openrouter', 'openai/gpt-4o-mini'),
      ThinkLevel.faible,
    );
    sessions.continueSession(run.id, 'Et un lien dans le menu');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (var i = 0; i < 200 && run.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(run.summary, 'Fait');
    expect(hosts, everyElement('openrouter.ai'));
    expect(usageState.of('openrouter').requestsTotal, greaterThan(0));
    expect(usageState.of('groq').requestsTotal, 0);
  });
}

/// Un compte GitHub simulé : un dépôt vide, lisible.
class _FakeGitHub extends GitHubState {
  _FakeGitHub(super.storage);

  final _fake = GitHubApi(
    't',
    client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
  );

  @override
  GitHubApi get api => _fake;
}
