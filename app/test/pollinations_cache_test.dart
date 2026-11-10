import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse sse(Map<String, dynamic> event) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode('data: ${jsonEncode(event)}\n\n'),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

Map<String, dynamic> text(String t) => {
  'choices': [
    {
      'delta': {'content': t},
    },
  ],
};

/// L'erreur que Pollinations glisse dans le flux quand son modèle rate sa fin.
const upstream = {
  'error': {
    'message':
        'Chat Completions provider returned invalid or omitted terminal usage',
    'type': 'upstream_error',
    'code': 'usage_missing',
  },
};

final pollinations = providersCatalog.firstWhere((p) => p.id == 'pollinations');

/// Un faux Pollinations qui, comme le vrai, rejoue la réponse gardée en cache
/// pour une requête identique au caractère près.
http.Client Function() cachingServer(
  List<Map<String, dynamic>> bodies,
  Map<String, dynamic> Function(int n) answer,
) {
  final cache = <String, Map<String, dynamic>>{};
  return () => MockClient.streaming((req, body) async {
    final raw = await body.bytesToString();
    bodies.add(jsonDecode(raw) as Map<String, dynamic>);
    return sse(cache.putIfAbsent(raw, () => answer(cache.length)));
  });
}

void main() {
  test('chaque requête à Pollinations porte une graine nouvelle et reste '
      'privée (pas les autres fournisseurs)', () async {
    final bodies = <Map<String, dynamic>>[];
    final llm = LlmClient(
      clientFactory: cachingServer(bodies, (n) => text('réponse $n')),
    );
    Future<String> ask(String provider) => llm.complete(
      provider: providersCatalog.firstWhere((p) => p.id == provider),
      apiKey: 'k',
      model: 'openai',
      messages: const [LlmMessage('user', 'Un nombre au hasard')],
    );
    final first = await ask('pollinations');
    final again = await ask('pollinations');
    // « Régénérer » donne une nouvelle réponse, pas celle du cache.
    expect(again, isNot(first));
    expect(bodies[0]['seed'], isA<int>());
    expect(bodies[0]['seed'], isNot(bodies[1]['seed']));
    expect(bodies[0]['private'], isTrue);

    await ask('groq');
    expect(bodies.last.containsKey('seed'), isFalse);
    expect(bodies.last.containsKey('private'), isFalse);
  });

  test('une panne passagère de Pollinations ne se rejoue plus à chaque '
      'nouvel essai : l\'agent repart et termine', () async {
    final bodies = <Map<String, dynamic>>[];
    final run = AgentRun(
      llm: LlmClient(
        // La première réponse est une panne ; un essai différent réussit.
        clientFactory: cachingServer(
          bodies,
          (n) => n == 0
              ? upstream
              : text(
                  '```json\n{"tool": "finish", "args": {"summary": "Fait"}}\n```',
                ),
        ),
      ),
      github: GitHubApi(
        't',
        client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
      ),
      provider: pollinations,
      apiKey: null,
      model: 'openai',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Termine',
    )..retryPause = Duration.zero;
    await run.run();
    expect(run.summary, 'Fait');
    expect(run.finished, isTrue);
    expect(bodies.length, greaterThanOrEqualTo(2));
    expect(
      run.steps.where((s) => s.kind == StepKind.error).single.text,
      contains('Nouvel essai (1/2)'),
    );
  });
}
