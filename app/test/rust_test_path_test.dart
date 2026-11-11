import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

// Le site de NEXORA : une bibliothèque (îlots) et un programme (les routes).
const _site = [
  'site/Cargo.toml',
  'site/src/lib.rs',
  'site/src/main.rs',
  'site/tests/iles.rs',
];

/// Ce que la traduction a vraiment rendu pour « ajoute une route GET /sante
/// au site, avec un test Rust » (essai avec Pollinations).
const _spec =
    'OBJECTIF : Ajouter une route GET /sante qui renvoie « ok ».\n\n'
    'DEMANDES :\n'
    '1. Dans site/src/main.rs, ajouter une route GET /sante.\n'
    '2. Créer un fichier de test Rust (site/tests/sante_test.rs) qui vérifie '
    'la réponse.\n\n'
    'CRITÈRES DE RÉUSSITE :\n'
    '- Le test site/tests/sante_test.rs passe sans erreur.';

void main() {
  test('un test de route du programme ne va plus dans tests/', () {
    final out = AgentRun.fixRustTestPaths(_spec, _site);
    expect(out, isNot(contains('site/tests/sante_test.rs')));
    expect(
      out,
      contains(
        'site/src/main.rs (dans son module « #[cfg(test)] mod tests », pas '
        'dans site/tests/ qui ne voit pas le programme)',
      ),
    );
    // Le reste de la demande est gardé tel quel.
    expect(out, contains('1. Dans site/src/main.rs, ajouter une route GET'));
  });

  test('programme sans bibliothèque : tests/ ne voit jamais rien', () {
    const spec = 'DEMANDES :\n1. Créer tests/outil.rs pour tester parse().';
    final out = AgentRun.fixRustTestPaths(spec, ['Cargo.toml', 'src/main.rs']);
    expect(out, contains('src/main.rs (dans son module'));
    expect(out, isNot(contains('tests/outil.rs')));
  });

  test('ce qui reste juste ne change pas', () {
    // Un fichier de tests qui existe déjà.
    const existing = 'DEMANDES :\n1. Compléter site/tests/iles.rs.';
    expect(AgentRun.fixRustTestPaths(existing, _site), existing);
    // Un test de la bibliothèque (src/lib.rs), qui compile dans tests/.
    const lib =
        'DEMANDES :\n1. Modifier site/src/lib.rs.\n'
        '2. Créer site/tests/scene.rs.';
    expect(AgentRun.fixRustTestPaths(lib, _site), lib);
    // La demande ne touche pas au programme : rien n'est supposé.
    const other = 'DEMANDES :\n1. Créer site/tests/contenu.rs.';
    expect(AgentRun.fixRustTestPaths(other, _site), other);
    // Pas de projet Rust reconnu.
    const plain = 'DEMANDES :\n1. Créer tests/a.rs.';
    expect(AgentRun.fixRustTestPaths(plain, ['README.md']), plain);
  });

  test('la demande donnée à l\'agent ne cite plus le mauvais chemin', () async {
    final sent = <String>[];
    var calls = 0;
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          sent.add(
            (j['messages'] as List)
                .map((m) => (m as Map)['content'].toString())
                .join('\n'),
          );
          // D'abord la traduction, puis l'agent s'arrête.
          final r = calls++ == 0
              ? _spec
              : '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
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
                  for (final p in _site) {'path': p, 'type': 'blob'},
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
      owner: 'o',
      repo: 'r',
      branch: 'main',
      task: 'Ajoute une route GET /sante au site, avec un test Rust.',
    );
    AgentRun.compile = true;
    try {
      await run.run();
    } finally {
      AgentRun.compile = false;
    }
    expect(sent.length, greaterThanOrEqualTo(2));
    final agent = sent[1];
    expect(agent, contains('OBJECTIF : Ajouter une route GET /sante'));
    expect(agent, isNot(contains('site/tests/sante_test.rs')));
    expect(agent, contains('dans son module « #[cfg(test)] mod tests »'));
  });
}
