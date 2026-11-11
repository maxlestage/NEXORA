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

const mainRs = '''use paquets::prelude::*;

async fn accueil(_req: Request) -> Page {
    page("/")
}

async fn robots(_req: Request) -> String {
    "User-agent: *".into()
}

fn app() -> App {
    let mut app = App::new();
    app.get("/", accueil);
    app.get("/robots.txt", robots);
    app
}
''';

/// L'agent cherche [query] dans site/src/main.rs puis s'arrête ; rend le
/// résultat de la recherche tel que le modèle l'a reçu.
Future<String> search(String query) async {
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
                {'path': 'site/src/main.rs', 'type': 'blob'},
              ],
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/contents/site/src/main.rs')) {
          return http.Response(
            jsonEncode({
              'sha': 's',
              'content': base64.encode(utf8.encode(mainRs)),
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
    repo: 'nexora',
    branch: 'main',
    task: 'Trouve les pages',
  )..specs.add('déjà compris');
  await run.run();
  expect(run.summary, 'Cherché');
  return run.history
      .firstWhere((m) => m.content.startsWith('Résultat de search_code'))
      .content;
}

void main() {
  AgentRun.checks = false;

  group('quand une recherche est une expression régulière', () {
    test('les motifs courants sont reconnus', () {
      for (final q in [
        r'async fn .* -> String',
        r'fn (accueil|robots)',
        r'^use ',
        r'app\.get\(',
        r'\bApp\b',
        r'(?i)robots',
        r'Page$',
      ]) {
        expect(AgentRun.regexQuery(q), isNotNull, reason: q);
      }
    });

    test('un texte simple reste un texte simple', () {
      for (final q in [
        'app()',
        '#[tokio::test]',
        'send("',
        'mod tests',
        '-> String',
        'Response::new()',
      ]) {
        expect(AgentRun.regexQuery(q), isNull, reason: q);
      }
    });

    test('invalide, ou qui trouverait n\'importe quelle ligne : ignorée', () {
      expect(AgentRun.regexQuery(r'fn (a|b'), isNull);
      expect(AgentRun.regexQuery('a || b'), isNull);
      expect(AgentRun.regexQuery('.*'), isNull);
    });
  });

  test('« async fn .* -> String » trouve la fonction qui rend un String '
      '(avant : « Aucune ligne »)', () async {
    final result = await search(r'async fn .* -> String');
    expect(result, contains('expression régulière'));
    expect(result, contains('>7: async fn robots(_req: Request) -> String {'));
    expect(result, isNot(contains('Aucune ligne')));
    expect(result, isNot(contains('>3: async fn accueil')));
  });

  test('une alternative « get|post » trouve chaque route', () async {
    final result = await search(r'app\.get\("/(robots|inconnu)');
    expect(result, contains('>14:     app.get("/robots.txt", robots);'));
  });

  test('un texte qui existe tel quel est cherché tel quel', () async {
    final result = await search('app()');
    expect(result, isNot(contains('expression régulière')));
    expect(result, contains('>11: fn app() -> App {'));
  });
}
