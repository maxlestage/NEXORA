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

/// L'agent fait [before], cherche [query] puis s'arrête ; rend le résultat
/// de la recherche reçu par le modèle.
Future<String> search(
  String query,
  Map<String, String> files, {
  String? path,
  List<Map<String, dynamic>> before = const [],
}) async {
  final replies = [
    for (final a in before) '```json\n${jsonEncode(a)}\n```',
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
    task: 'Dans site/, ajoute une route /sante qui répond ok en texte brut',
  )..specs.add('déjà compris');
  await run.run();
  expect(run.summary, 'Cherché');
  return run.history
      .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
      .content;
}

const mainRs = '''use paquets::prelude::*;

async fn sitemap(_req: Request) -> Response {
    Response::new()
        .header("content-type", "application/xml; charset=utf-8")
        .body(String::new())
}

async fn robots(_req: Request) -> String {
    "User-agent: *".into()
}

fn app() -> App {
    let mut app = App::new();
    app.get("/sitemap.xml", sitemap);
    app.get("/robots.txt", robots);
    app
}
''';

void main() {
  AgentRun.checks = false;

  test('le nom dont on cherche la définition', () {
    expect(AgentRun.definedName('pub struct Response'), 'Response');
    expect(AgentRun.definedName('struct Response'), 'Response');
    expect(AgentRun.definedName('pub(crate) enum Mode {'), 'Mode');
    expect(AgentRun.definedName('pub async fn sante('), 'sante');
    expect(AgentRun.definedName('trait Handler'), 'Handler');
    expect(AgentRun.definedName('abstract class Store'), 'Store');
    expect(AgentRun.definedName('class Foo<T>'), isNull);
    expect(AgentRun.definedName('Response'), isNull);
    expect(AgentRun.definedName('async fn .* -> String'), isNull);
    expect(AgentRun.definedName('fn app() -> App'), isNull);
    expect(AgentRun.definedName('the struct is here'), isNull);
  });

  test('essai réel : la définition d\'un type venu d\'une dépendance n\'est '
      'plus cherchée en boucle, l\'usage existant est montré', () async {
    final r = await search('pub struct Response', {
      'site/src/main.rs': mainRs,
      'site/Cargo.toml': '[dependencies]\npaquets = "1"\n',
    });
    expect(r, contains('« Response » vient d\'une dépendance'));
    expect(r, contains('Ne la cherche plus'));
    expect(r, contains('>4:     Response::new()'));
    expect(r, contains('.header("content-type"'));
    expect(r, isNot(contains('Essaie un mot plus court')));
  });

  test('cherchée dans un dossier : même réponse', () async {
    final r = await search('struct Response', {
      'site/src/main.rs': mainRs,
    }, path: 'site/src');
    expect(r, contains('« Response » vient d\'une dépendance'));
  });

  test('un nom que seul un brouillon utilise est à créer', () async {
    final r = await search(
      'async fn sante',
      {'site/src/main.rs': mainRs},
      before: [
        {
          'tool': 'edit_file',
          'args': {
            'path': 'site/src/main.rs',
            'old': '    app.get("/robots.txt", robots);\n',
            'new':
                '    app.get("/robots.txt", robots);\n'
                '    app.get("/sante", sante);\n',
          },
        },
      ],
    );
    expect(r, contains('« sante » n\'est défini nulle part'));
    expect(r, contains('app.get("/sante", sante);'));
    expect(r, contains('crée sa définition maintenant'));
    expect(r, isNot(contains('vient d\'une dépendance')));
  });

  test('un nom inconnu partout garde la réponse habituelle', () async {
    final r = await search('fn sante', {'site/src/main.rs': mainRs});
    expect(r, contains('Aucune ligne ne contient « fn sante »'));
    expect(r, isNot(contains('dépendance')));
  });

  test('une définition présente est trouvée normalement', () async {
    final r = await search('async fn robots', {'site/src/main.rs': mainRs});
    expect(r, contains('1 ligne(s) contiennent « async fn robots »'));
  });
}
