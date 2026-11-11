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

// Ce que l'essai réel trouvait pour « utils » dans l'app : des « outils ».
const agentDart = '''/// Un agent : un nom, une consigne système, des outils.
class Agent {
  /// Outils autorisés en mode autonome (vide : tous).
  final List<String> tools = [];
}
''';

/// L'agent cherche [query] puis s'arrête ; rend le résultat reçu par le modèle.
Future<String> search(String query, Map<String, String> files) async {
  final replies = [
    '```json\n${jsonEncode({
      'tool': 'search_code',
      'args': {'query': query},
    })}\n```',
    '```json\n${jsonEncode({
      'tool': 'finish',
      'args': {'summary': 'Cherché'},
    })}\n```',
  ];
  var i = 0;
  final run = AgentRun(
    llm: LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        await body.drain<void>();
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
                for (final p in files.keys) {'path': p, 'type': 'blob'},
              ],
            }),
            200,
          );
        }
        for (final e in files.entries) {
          if (req.url.path.endsWith('/contents/${e.key}')) {
            return http.Response(
              jsonEncode({
                'sha': 's',
                'content': base64.encode(utf8.encode(e.value)),
                'encoding': 'base64',
              }),
              200,
            );
          }
        }
        return http.Response('{"message":"Not Found"}', 404);
      }),
    ),
    provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
    apiKey: null,
    model: 'openai',
    owner: 'max',
    repo: 'nexora',
    branch: 'main',
    task: 'Ajoute formatDuree dans lib/utils',
  )..specs.add('déjà compris');
  await run.run();
  expect(run.summary, 'Cherché');
  return run.history
      .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
      .content;
}

void main() {
  AgentRun.checks = false;

  test('un mot entier, pas la fin d\'un autre mot', () {
    expect(AgentRun.wholeWord('des outils', 'utils'), isFalse);
    expect(AgentRun.wholeWord('/// Outils autorisés', 'utils'), isFalse);
    expect(AgentRun.wholeWord("import 'utils.dart';", 'utils'), isTrue);
    expect(AgentRun.wholeWord('lib/utils/duree.dart', 'utils'), isTrue);
    expect(AgentRun.wholeWord('my_utils()', 'utils'), isTrue);
    // Le début d'un mot en camelCase compte.
    expect(AgentRun.wholeWord('String formatDuree(d)', 'duree'), isTrue);
    expect(AgentRun.wholeWord('outils puis utils', 'utils'), isTrue);
  });

  test('« utils » seulement dans « outils » : l\'agent sait que le nom '
      'n\'existe pas', () async {
    final r = await search('utils', {'app/lib/models/agent.dart': agentDart});
    expect(r, contains('Aucune ligne ne contient « utils » comme nom'));
    expect(r, contains('« outils »'));
    expect(r, contains('« Outils »'));
    expect(r, contains('n\'existe donc pas encore'));
    expect(r, contains('crée-le'));
    expect(r, isNot(contains('agent.dart:1')));
  });

  test(
    'les vraies correspondances d\'abord, les autres mots écartés',
    () async {
      final r = await search('utils', {
        'app/lib/models/agent.dart': agentDart,
        'app/lib/main.dart': "import 'utils.dart';\nvoid main() {}\n",
      });
      expect(
        r,
        contains('1 ligne(s) contiennent « utils » (le mot lui-même ; '),
      );
      expect(r, contains("import 'utils.dart';"));
      expect(r, isNot(contains('des outils')));
    },
  );

  test('une recherche sans faux amis ne change pas', () async {
    final r = await search('agent', {'app/lib/models/agent.dart': agentDart});
    expect(r, startsWith('Résultat de search_code'));
    expect(r, contains('ligne(s) contiennent « agent », avec le code'));
    expect(r, isNot(contains('le mot lui-même')));
  });
}
