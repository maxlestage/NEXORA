import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse text(String t) => http.StreamedResponse(
  Stream.fromIterable(
    [
      'data: ${jsonEncode({
        'choices': [
          {
            'index': 0,
            'delta': {'content': t},
          },
        ],
      })}\n\n',
      'data: [DONE]\n\n',
    ].map(utf8.encode),
  ),
  200,
  headers: {'content-type': 'text/event-stream'},
);

void main() {
  AgentRun.checks = false;

  group('les lignes à lire, quel que soit le nom des arguments', () {
    test('start/end, offset/limit (comme avant)', () {
      expect(AgentRun.readSpan({'start': 10, 'end': 20}), (10, 20, null));
      expect(AgentRun.readSpan({'offset': 10, 'limit': 5}), (10, 15, null));
      expect(AgentRun.readSpan({'line': 50}), (null, null, 50));
      expect(AgentRun.readSpan({}), (null, null, null));
    });

    test('line_start/line_end, start_line/end_line, from/to', () {
      expect(AgentRun.readSpan({'line_start': 1800, 'line_end': 1845}), (
        1800,
        1845,
        null,
      ));
      expect(AgentRun.readSpan({'start_line': '12', 'end_line': '30'}), (
        12,
        30,
        null,
      ));
      expect(AgentRun.readSpan({'from': 5, 'to': 9}), (5, 9, null));
    });

    test('lines « 10-20 » ou [10, 20], et line avec une fin', () {
      expect(AgentRun.readSpan({'lines': '10-20'}), (10, 20, null));
      expect(
        AgentRun.readSpan({
          'range': [10, 20],
        }),
        (10, 20, null),
      );
      expect(AgentRun.readSpan({'line': 1, 'end': 400}), (1, 400, null));
    });
  });

  test('une lecture par line_start/line_end rend ces lignes, pas le début du '
      'fichier', () async {
    final file = [for (var i = 1; i <= 2000; i++) 'ligne numéro $i'].join('\n');
    final requests = <String>[];
    final replies = [
      '```json\n${jsonEncode({
        'tool': 'repo_browser.open_file',
        'args': {'path': 'src/main.rs', 'line_start': 1800, 'line_end': 1805},
      })}\n```',
      '```json\n${jsonEncode({
        'tool': 'finish',
        'args': {'summary': 'Lu'},
      })}\n```',
    ];
    var i = 0;
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          requests.add(await body.bytesToString());
          return text(replies[i++]);
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
          if (req.url.path.endsWith('/contents/src/main.rs')) {
            return http.Response(
              jsonEncode({
                'sha': 's',
                'content': base64.encode(utf8.encode(file)),
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
      model: 'openai',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Lis la fin du fichier',
    )..specs.add('déjà compris');
    await run.run();
    expect(run.summary, 'Lu');
    final seen = requests[1];
    expect(seen, contains('ligne numéro 1800'));
    expect(seen, contains('ligne numéro 1805'));
    expect(seen, isNot(contains('ligne numéro 1806')));
    expect(seen, isNot(contains('ligne numéro 1\\n')));
    expect(seen, contains('Lignes 1800 à 1805 sur 2000'));
  });
}
