import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

const _tree = [
  'site/Cargo.toml',
  'site/src/lib.rs',
  'site/src/main.rs',
  'site/src/contenu.rs',
  'site/tests/degrades.rs',
];

const _said =
    'Dans site/src/contenu.rs, fais reconnaître les points qui commencent par '
    '« Retiré » comme une nature à part, dans nature() et dans '
    'sans_etiquette(). Ajoute un test.';

// Ce que la traduction a vraiment rendu (essai avec Pollinations).
const _spec =
    'DEMANDES :\n'
    '1. Dans *site/src/contenu.rs*, modifier la fonction *nature()*.\n'
    '3. Créer un fichier de test *site/tests/retrait_test.rs* qui vérifie '
    'nature().\n\n'
    'CRITÈRES DE RÉUSSITE :\n'
    '- Le test `retrait_test.rs` doit vérifier que nature() retourne « Retiré ».';

const _contenu =
    'pub fn nature(p: &str) -> &str { p }\n\n'
    '#[cfg(test)]\nmod tests_nature {\n    use super::*;\n}\n';

void main() {
  test(
    'les fichiers à lire : ceux de src/ cités, à côté d\'un nouveau test',
    () {
      expect(AgentRun.rustSourcesFor(_spec, _tree), ['site/src/contenu.rs']);
      // Le fichier de tests existe déjà : rien à lire.
      expect(
        AgentRun.rustSourcesFor(
          'DEMANDES :\n1. Dans site/src/contenu.rs…\n2. Compléter '
          'site/tests/degrades.rs.',
          _tree,
        ),
        isEmpty,
      );
    },
  );

  test('essai réel : le test va dans le module de tests existant', () {
    final out = AgentRun.preferTestModule(_spec, _said, {
      'site/src/contenu.rs': _contenu,
    });
    expect(out, isNot(contains('site/tests/retrait_test.rs')));
    expect(
      out,
      contains(
        'site/src/contenu.rs (dans son module « #[cfg(test)] » existant, '
        'avec les autres tests',
      ),
    );
    // Son nom seul, dans les critères, aussi.
    expect(out, contains('module de tests de site/src/contenu.rs'));
    expect(out, isNot(contains('retrait_test.rs')));
    // Le reste de la demande ne change pas.
    expect(out, contains('1. Dans *site/src/contenu.rs*, modifier'));
  });

  test('ce qui doit rester ne change pas', () {
    // Le fichier modifié n'a pas encore de tests.
    expect(
      AgentRun.preferTestModule(_spec, _said, {
        'site/src/contenu.rs': 'pub fn nature() {}\n',
      }),
      _spec,
    );
    // L'utilisateur a nommé le fichier de tests.
    expect(
      AgentRun.preferTestModule(_spec, '$_said Mets-le dans retrait_test.rs.', {
        'site/src/contenu.rs': _contenu,
      }),
      _spec,
    );
    // Deux fichiers modifiés avec des tests : on ne choisit pas.
    expect(
      AgentRun.preferTestModule(_spec, _said, {
        'site/src/contenu.rs': _contenu,
        'site/src/lib.rs': _contenu,
      }),
      _spec,
    );
    // Un autre crate (autre dossier) : pas concerné.
    expect(
      AgentRun.preferTestModule(
        'DEMANDES :\n1. Créer outil/tests/a.rs.',
        _said,
        {'site/src/contenu.rs': _contenu},
      ),
      'DEMANDES :\n1. Créer outil/tests/a.rs.',
    );
  });

  test('dans une vraie session, même loin dans un gros dépôt', () async {
    final sent = <String>[];
    var calls = 0;
    // Plus de 300 fichiers avant le site : la liste montrée au traducteur
    // est raccourcie, site/src/contenu.rs n'y est pas.
    final tree = [for (var i = 0; i < 400; i++) 'app/lib/f$i.dart', ..._tree];
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final j = jsonDecode(await body.bytesToString()) as Map;
          sent.add(
            (j['messages'] as List)
                .map((m) => (m as Map)['content'].toString())
                .join('\n'),
          );
          final r = calls++ == 0
              ? 'OBJECTIF : Reconnaître « Retiré » dans nature().\n\n$_spec'
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
                  for (final p in tree) {'path': p, 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          if (req.url.path.endsWith('/contents/site/src/contenu.rs')) {
            return http.Response(
              jsonEncode({
                'sha': 'c',
                'content': base64.encode(utf8.encode(_contenu)),
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
      owner: 'o',
      repo: 'r',
      branch: 'main',
      task: _said,
    );
    AgentRun.compile = true;
    try {
      await run.run();
    } finally {
      AgentRun.compile = false;
    }
    expect(sent.length, greaterThanOrEqualTo(2));
    expect(sent[1], isNot(contains('retrait_test.rs')));
    expect(sent[1], contains('module « #[cfg(test)] » existant'));
  });
}
