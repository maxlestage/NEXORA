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
    task: 'Ajoute une page /faq au site',
  )..specs.add('déjà compris');
  await run.run();
  expect(run.summary, 'Cherché');
  return run.history
      .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
      .content;
}

/// Essai réel : depuis site/src/main.rs, l'agent cherchait « const FAQ »,
/// défini dans site/src/contenu.rs. La recherche élargie à tout le dépôt
/// s'arrête à 300 fichiers, parcourus dans l'ordre du dépôt : les centaines de
/// fichiers de app/ passaient avant, contenu.rs n'était jamais lu, et l'agent
/// refaisait la même recherche jusqu'à l'arrêt de la session.
void main() {
  AgentRun.checks = false;

  test('searchRank : les voisins du fichier visé d\'abord', () {
    const near = 'site/src/main.rs';
    expect(AgentRun.searchRank('site/src/contenu.rs', ['faq'], near), 1);
    expect(AgentRun.searchRank('app/lib/faq_screen.dart', ['faq'], near), 2);
    expect(AgentRun.searchRank('site/tests/iles.rs', ['faq'], near), 3);
    expect(AgentRun.searchRank('app/lib/main.dart', ['faq'], near), 4);
    // Un dossier visé : ses fichiers d'abord.
    expect(AgentRun.searchRank('site/src/a.rs', [], 'site/src'), 1);
    expect(AgentRun.searchRank('site/src/a.rs', [], 'site/src/'), 1);
    expect(AgentRun.searchRank('site/tests/a.rs', [], 'site/src'), 3);
    // Sans fichier visé : le nom, puis le reste, comme avant.
    expect(AgentRun.searchRank('site/faq.rs', ['faq'], ''), 2);
    expect(AgentRun.searchRank('site/a.rs', ['faq'], ''), 4);
  });

  test('cherché dans main.rs, trouvé dans contenu.rs malgré 320 fichiers '
      'dans app/', () async {
    final r = await search('const FAQ', {
      for (var i = 0; i < 320; i++)
        'app/lib/f${i.toString().padLeft(3, '0')}.dart': 'void f() {}\n',
      'site/src/contenu.rs':
          '/// La FAQ.\npub const FAQ: [(&str, &str); 1] = [("Q", "R")];\n',
      'site/src/main.rs': 'fn faq() {\n    faq_liste(&FAQ);\n}\n',
    }, path: 'site/src/main.rs');
    expect(r, contains('Dans tout le dépôt'));
    expect(r, contains('site/src/contenu.rs :'));
    expect(r, contains('>2: pub const FAQ'));
  });

  test('cherché dans chat_state.dart, défini dans models/chat.dart : pas de '
      '« dépendance externe » contredite ensuite', () async {
    // Essai réel : « class Conversation » cherché dans chat_state.dart
    // répondait « vient d'une dépendance, ne la cherche plus », puis la vraie
    // définition ; l'agent tournait en rond jusqu'à l'arrêt.
    final r = await search('class Conversation', {
      'app/lib/state/chat_state.dart':
          "import '../models/chat.dart';\n\nclass ChatState {\n"
          '  final List<Conversation> _conversations = [];\n}\n',
      'app/lib/models/chat.dart': '/// Une conversation.\nclass Conversation {\n  String title = \'\';\n}\n',
    }, path: 'app/lib/state/chat_state.dart');
    expect(r, isNot(contains('dépendance')));
    expect(r, isNot(contains('Ne la cherche plus')));
    expect(r, contains('Rien dans app/lib/state/chat_state.dart'));
    expect(r, contains('app/lib/models/chat.dart :'));
    expect(r, contains('>2: class Conversation {'));
  });
}
