import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

// Les fichiers du dépôt NEXORA : l'app Flutter et le site Rust (bibliothèque
// et programme).
const _nexora = [
  '.github/workflows/ci.yml',
  'app/pubspec.yaml',
  'app/lib/main.dart',
  'app/lib/ui/home.dart',
  'app/test/app_test.dart',
  'site/Cargo.toml',
  'site/src/lib.rs',
  'site/src/main.rs',
  'site/tests/iles.rs',
];

void main() {
  test('NEXORA : tests Dart dans app/test, routes du site dans main.rs', () {
    final l = AgentRun.testLayout(_nexora);
    expect(l, contains('app/ (Dart/Flutter) : app/test/<nom>_test.dart'));
    expect(l, contains('flutter_test'));
    expect(l, isNot(contains('dossier à créer')));
    expect(l, contains('site/ (Rust) : site/tests/<nom>.rs'));
    expect(
      l,
      contains(
        'Ce qui est défini dans site/src/main.rs (routes, app(), fonctions du '
        'programme) se teste UNIQUEMENT dans son module « #[cfg(test)] mod '
        'tests »',
      ),
    );
  });

  test('programme Rust sans bibliothèque : jamais tests/', () {
    final l = AgentRun.testLayout(['Cargo.toml', 'src/main.rs', 'README.md']);
    expect(l, startsWith('- la racine (Rust, programme sans bibliothèque)'));
    expect(l, contains('src/main.rs'));
    expect(l, contains('Jamais dans tests/'));
  });

  test('bibliothèque Rust seule : tests/, sans parler de main.rs', () {
    final l = AgentRun.testLayout(['Cargo.toml', 'src/lib.rs']);
    expect(l, contains('tests/<nom>.rs'));
    expect(l, isNot(contains('main.rs')));
  });

  test('JavaScript, Python, Go et Dart sans dossier de tests', () {
    final l = AgentRun.testLayout([
      'web/package.json',
      'web/__tests__/a.test.js',
      'api/pyproject.toml',
      'api/setup.py',
      'cli/go.mod',
      'pkg/pubspec.yaml',
      'pkg/lib/pkg.dart',
    ]);
    expect(l, contains('web/ (JavaScript/TypeScript) : web/__tests__/'));
    expect(l, contains('api/ (Python) : api/tests/test_<nom>.py'));
    expect('(Python)'.allMatches(l), hasLength(1));
    expect(l, contains('cli/ (Go) : <nom>_test.go'));
    expect(l, contains('pkg/test/<nom>_test.dart (dossier à créer)'));
    expect(l, contains('package:test'));
  });

  test('ni dépendances ni projet inconnu', () {
    expect(AgentRun.testLayout(['node_modules/x/package.json']), isEmpty);
    expect(AgentRun.testLayout(['README.md', 'index.html']), isEmpty);
  });

  test('la traduction reçoit le repère des projets qu\'elle concerne', () {
    final layout = AgentRun.testLayout(_nexora);
    const spec =
        'OBJECTIF : ajouter une route /sante au site.\n'
        'DEMANDES :\n1. Modifier site/src/main.rs.\n'
        '2. Créer site/tests/sante_test.rs.';
    final out = AgentRun.withTestLayout(spec, layout);
    expect(out, startsWith(spec));
    expect(out, contains('OÙ VONT LES TESTS'));
    expect(out, contains('prime sur tout autre chemin de test'));
    expect(out, contains('UNIQUEMENT dans son module « #[cfg(test)]'));
    // L'app Flutter n'est pas concernée : pas de ligne pour elle.
    expect(out, isNot(contains('Dart/Flutter')));
    // Sans traduction ou sans projet reconnu : rien n'est ajouté.
    expect(AgentRun.withTestLayout('', layout), isEmpty);
    expect(AgentRun.withTestLayout(spec, ''), spec);
    // Un seul projet : toujours donné, même si la traduction ne le nomme pas.
    final one = AgentRun.testLayout(['Cargo.toml', 'src/main.rs']);
    expect(
      AgentRun.withTestLayout('OBJECTIF : une route.', one),
      contains('Jamais dans tests/'),
    );
  });

  test('le repère est donné à l\'agent dès le premier message', () async {
    final sent = <String>[];
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          sent.add(
            (j['messages'] as List)
                .map((m) => (m as Map)['content'].toString())
                .join('\n'),
          );
          final r = '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'index': 0,
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
      ),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  for (final p in _nexora) {'path': p, 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          return http.Response('{"message":"Not Found"}', 404);
        }),
      ),
      provider: providersCatalog.first,
      apiKey: 'k',
      model: 'm',
      owner: 'o',
      repo: 'r',
      branch: 'main',
      task: 'Ajoute une route /sante au site, avec son test.',
    );
    await run.run();
    expect(sent, isNotEmpty);
    expect(
      sent.first,
      contains('OÙ ÉCRIRE LES TESTS (inutile de le chercher)'),
    );
    expect(sent.first, contains('son module « #[cfg(test)] mod tests »'));
  });
}
