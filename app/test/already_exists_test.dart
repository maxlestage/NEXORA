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

String action(String tool, Map<String, Object> args) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```';

const mainRs = '''
fn app() -> App {
    let mut app = App::new();
    app.get("/faq", faq);
    app
}

async fn faq(_req: Request) -> Page {
    page("/faq", "Questions fréquentes")
}
''';

/// Essai réel : « ajoute une page /faq… » alors que la page existe déjà. Le
/// modèle trouvait la route, puis refaisait la même recherche ; les relances lui
/// affirmaient « ce que tu cherches N'EXISTE PAS » et « fais la première
/// modification », et la session s'arrêtait sans rien dire.
void main() {
  setUp(() => AgentRun.checks = false);
  tearDown(() => AgentRun.checks = true);

  late List<String> prompts;

  AgentRun build(String query) {
    prompts = [];
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final msgs =
              (jsonDecode(await body.bytesToString()) as Map)['messages']
                  as List;
          final last = (msgs.last as Map)['content'].toString();
          prompts.add(last);
          // Une fois prévenu que la demande existe peut-être déjà, il le dit.
          if (last.contains('EXISTE PEUT-ÊTRE DÉJÀ')) {
            return sse(
              action('finish', {
                'summary': 'La page /faq existe déjà (site/src/main.rs).',
              }),
            );
          }
          return sse(
            action('search_code', {'query': query, 'path': 'site/src/main.rs'}),
          );
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
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'nexora',
      branch: 'main',
      task: 'Ajoute une page /faq au site',
    )..specs.add('déjà compris');
  }

  test('foundSomething : une recherche avec des lignes, pas un échec', () {
    expect(
      AgentRun.foundSomething(
        'search_code',
        'Résultat de search_code :\n2 ligne(s) contiennent « faq » :',
      ),
      isTrue,
    );
    expect(
      AgentRun.foundSomething(
        'search_code',
        'Aucune ligne ne contient « faq » (1 fichiers parcourus).',
      ),
      isFalse,
    );
    expect(AgentRun.foundSomething('find_in_file', 'ERREUR : x'), isFalse);
    expect(
      AgentRun.foundSomething('find_in_file', 'Fichier introuvable : a.rs'),
      isFalse,
    );
    // Lire ou lister ne prouve pas que la demande est déjà faite.
    expect(AgentRun.foundSomething('read_file', 'fn faq() {}'), isFalse);
    expect(AgentRun.foundSomething('list_files', 'site/src/main.rs'), isFalse);
  });

  test('la même recherche refaite alors qu\'elle trouve : l\'agent apprend que '
      'la demande existe peut-être déjà, et termine en le disant', () async {
    final run = build('fn faq');
    await run.run();
    // Plus jamais « ça n'existe pas » quand la recherche a trouvé.
    expect(prompts.any((p) => p.contains('N\'EXISTE PAS')), isFalse);
    expect(prompts.any((p) => p.contains('EXISTE PEUT-ÊTRE DÉJÀ')), isTrue);
    expect(prompts.any((p) => p.contains('tes recherches TROUVENT')), isTrue);
    expect(run.summary, contains('existe déjà'));
    expect(run.steps.any((s) => s.text.contains('en boucle')), isFalse);
  });

  test('la même recherche refaite sans rien trouver : toujours « n\'existe '
      'pas »', () async {
    final run = build('compare_versions');
    await run.run();
    expect(prompts.any((p) => p.contains('N\'EXISTE PAS')), isTrue);
    expect(prompts.any((p) => p.contains('EXISTE PEUT-ÊTRE DÉJÀ')), isFalse);
    expect(run.steps.last.text, contains('en boucle'));
  });

  test('repeatNudge : la réponse recopiée est retirée, la relance rejoint le '
      'résultat et remplace la précédente', () {
    final h = [
      const LlmMessage('assistant', 'cherche FAQ'),
      const LlmMessage('user', 'Résultat de search_code :\n15 lignes'),
      const LlmMessage('assistant', 'cherche FAQ'),
    ];
    AgentRun.repeatNudge(h, 'relance 1');
    expect(h.length, 2);
    expect(h.last.role, 'user');
    expect(h.last.content, startsWith('Résultat de search_code :\n15 lignes'));
    expect(h.last.content, endsWith('relance 1'));
    h.add(const LlmMessage('assistant', 'cherche FAQ'));
    AgentRun.repeatNudge(h, 'relance 2');
    expect(h.length, 2);
    expect(h.last.content, isNot(contains('relance 1')));
    expect(h.last.content, endsWith('relance 2'));
    expect('ACTION DÉJÀ FAITE'.allMatches(h.last.content).length, 1);
    // Rien à fusionner : la relance est simplement ajoutée.
    final solo = [const LlmMessage('assistant', 'x')];
    AgentRun.repeatNudge(solo, 'r');
    expect(solo.map((m) => m.role), ['assistant', 'user']);
  });

  test('sans modification ni résultat trouvé, la note reste la même', () {
    final run = build('x');
    expect(run.progressNote(), contains('Fais MAINTENANT la première'));
    expect(run.progressNote(), isNot(contains('TROUVENT')));
  });
}
