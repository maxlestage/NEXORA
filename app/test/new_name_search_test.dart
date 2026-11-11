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

/// L'agent cherche [query] puis s'arrête ; rend le résultat reçu par le modèle.
Future<String> search(
  String query,
  Map<String, String> files, {
  String? path,
}) async {
  final replies = [
    '```json\n${jsonEncode({
      'tool': 'search_code',
      'args': {'query': query, 'path': ?path},
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
    task: 'Ajoute format_octets dans site/src/lib.rs, avec ses tests',
  )..specs.add('déjà compris');
  await run.run();
  expect(run.summary, 'Cherché');
  return run.history
      .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
      .content;
}

const libRs = '''//! Ce que le serveur et le navigateur partagent.
pub mod contenu;

/// Le titre de la page.
pub fn titre() -> &'static str {
    "NEXORA"
}
''';

void main() {
  AgentRun.checks = false;

  test('un nom de code composé, pas un mot ni une phrase', () {
    expect(AgentRun.isNewName('format_octets'), isTrue);
    expect(AgentRun.isNewName('formatDuree'), isTrue);
    expect(AgentRun.isNewName('FormatOctets'), isTrue);
    expect(AgentRun.isNewName('Slug::new'), isTrue);
    expect(AgentRun.isNewName('MAX_TAILLE'), isTrue);
    expect(AgentRun.isNewName('titre'), isFalse);
    expect(AgentRun.isNewName('Titre'), isFalse);
    expect(AgentRun.isNewName('format octets'), isFalse);
    expect(AgentRun.isNewName('README.md'), isFalse);
    expect(AgentRun.isNewName('fn .* -> String'), isFalse);
    expect(AgentRun.isNewName('_'), isFalse);
  });

  test('essai réel : « format_octets » introuvable, l\'agent sait qu\'il '
      'doit le créer', () async {
    final r = await search('format_octets', {'site/src/lib.rs': libRs});
    expect(r, contains('« format_octets » n\'existe pas encore'));
    expect(r, contains('tout le dépôt'));
    expect(r, contains('crée-le maintenant'));
    expect(r, isNot(contains('Essaie un mot plus court')));
  });

  test(
    'cherché dans un fichier précis : la réponse vaut pour tout le dépôt',
    () async {
      final r = await search('format_octets', {
        'site/src/lib.rs': libRs,
        'site/src/main.rs': 'fn main() {}\n',
      }, path: 'site/src/lib.rs');
      expect(r, contains('« format_octets » n\'existe pas encore'));
      expect(r, contains('2 fichiers parcourus, tout le dépôt'));
    },
  );

  test('un nom qui existe sous une autre forme est toujours trouvé', () async {
    final r = await search('format_octets', {
      'site/src/lib.rs': '$libRs\npub fn formatOctets() {}\n',
    });
    expect(r, contains('formatOctets'));
    expect(r, isNot(contains('n\'existe pas encore')));
  });

  test('un simple mot introuvable garde le conseil habituel', () async {
    final r = await search('bonjour', {'site/src/lib.rs': libRs});
    expect(r, contains('Essaie un mot plus court'));
    expect(r, isNot(contains('n\'existe pas encore')));
  });
}
