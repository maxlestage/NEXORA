import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
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

String call(String tool, Map<String, Object> args) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```';

/// Un test coupé en deux : une « } » de trop (essai réel).
const broken =
    'fn version() -> String {\n'
    '    "1".into()\n'
    '}\n'
    '\n'
    '#[cfg(test)]\n'
    'mod tests {\n'
    '    #[test]\n'
    '    fn a() {\n'
    '        let x = 1;\n'
    '    }\n'
    '        assert_eq!(x, 1);\n'
    '    }\n'
    '}\n';

const valid = 'fn version() -> String {\n    "1".into()\n}\n';

void main() {
  setUp(() => AgentRun.checks = false);
  tearDown(() => AgentRun.checks = true);

  late List<String> prompts;

  AgentRun build(List<String> replies, {int maxSteps = 24}) {
    prompts = [];
    var n = 0;
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          final msgs = j['messages'] as List;
          prompts.add((msgs.last as Map)['content'].toString());
          final r = n < replies.length
              ? replies[n++]
              // Deux recherches refaites tour à tour (jamais deux fois de
              // suite la même).
              : call('search_code', {
                  'query': (n++).isOdd ? 'Response' : 'body',
                  'path': 'src',
                });
          return sse(r);
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  {'path': 'src/main.rs', 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          return http.Response('{"message":"Not Found"}', 404);
        }),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
      apiKey: null,
      model: 'openai',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Ajoute une route /version',
      maxSteps: maxSteps,
    );
  }

  test('le code cassé est rappelé quand l\'agent tourne en rond', () async {
    final run = build([
      call('write_file', {'path': 'src/lib.rs', 'content': broken}),
    ]);
    await run.run();
    // Juste après l'écriture : l'avertissement habituel.
    expect(prompts[1], contains('ne compilera pas'));
    expect(prompts[1], isNot(contains('AVANT TOUT')));
    // Puis, recherches refaites en rond : le rappel revient.
    final circling = prompts.where((p) => p.contains('tu tournes en rond'));
    expect(circling, isNotEmpty);
    for (final p in circling) {
      expect(p, contains('AVANT TOUT : tes brouillons ne compilent plus'));
      expect(p, contains('src/lib.rs ne compilera pas'));
    }
  });

  test('le code cassé est rappelé au point d\'étape', () async {
    final run = build([
      call('write_file', {'path': 'src/lib.rs', 'content': broken}),
      call('search_code', {'query': 'a', 'path': 'src'}),
      call('search_code', {'query': 'b', 'path': 'src'}),
    ], maxSteps: 3);
    await run.run();
    final point = prompts.firstWhere((p) => p.contains('étapes sans terminer'));
    expect(point, contains('AVANT TOUT : tes brouillons ne compilent plus'));
    expect(point, contains('src/lib.rs ne compilera pas'));
  });

  test('rien n\'est rappelé quand le code compile', () async {
    final run = build([
      call('write_file', {'path': 'src/lib.rs', 'content': valid}),
      call('search_code', {'query': 'a', 'path': 'src'}),
      call('search_code', {'query': 'b', 'path': 'src'}),
    ], maxSteps: 3);
    await run.run();
    expect(
      prompts.where((p) => p.contains('étapes sans terminer')),
      isNotEmpty,
    );
    expect(prompts.where((p) => p.contains('AVANT TOUT')), isEmpty);
  });
}
