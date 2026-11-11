import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'lib/a.dart', 'type': 'blob'},
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
      final r = i < replies.length
          ? replies[i++]
          : '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
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

AgentRun agent(List<String> replies) => AgentRun(
  llm: scripted(replies),
  github: fake(),
  provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
  apiKey: null,
  model: 'openai',
  owner: 'max',
  repo: 'app',
  branch: 'main',
  task: 'Ajoute un test',
);

/// Ce que renvoie vraiment le modèle « openai » de Pollinations : l'appel seul,
/// sans le contenu, puis il attend la réponse de l'outil.
const bare =
    '```json\n{"actions":[{"tool":"repo_browser.write_file","args":'
    '{"path":"test/a_test.dart"}}]}\n```';

const file =
    "import 'package:flutter_test/flutter_test.dart';\n\nvoid main() {}\n";

void main() {
  test('write_file sans contenu : le contenu suivant est écrit', () async {
    final run = agent([
      bare,
      '```dart\n$file```',
      '```json\n{"tool":"finish","args":{"summary":"Test ajouté"}}\n```',
    ]);
    await run.run();
    expect(run.changes['test/a_test.dart'], file);
    final results = run.steps.map((s) => s.text).join('\n');
    expect(results, contains('EN ATTENTE du contenu de test/a_test.dart'));
    expect(results, isNot(contains('en boucle')));
  });

  test('le contenu peut venir sans bloc de code', () async {
    final run = agent([
      bare,
      file,
      '{"tool":"finish","args":{"summary":"ok"}}',
    ]);
    await run.run();
    expect(run.changes['test/a_test.dart'], file);
  });

  test('une autre action après l\'attente reste cette action', () {
    expect(
      pendingContent(
        '```json\n{"tool":"read_file","args":{"path":"lib/a.dart"}}\n```',
      ),
      isNull,
    );
    // L'appel répété, cette fois avec son contenu : rien à rattraper.
    expect(pendingContent('$bare\n```dart\n$file```'), isNull);
    // L'appel seul, encore sans contenu : toujours rien à écrire.
    expect(pendingContent(bare), isNull);
    expect(pendingContent('```dart\n$file```'), file);
  });

  test('le contenu sous un autre nom est accepté', () {
    final calls = parseToolCalls(
      '{"tool":"write_file","args":{"path":"a.txt","contents":"bonjour"}}',
    );
    expect(calls.single.args['content'], 'bonjour');
  });
}
