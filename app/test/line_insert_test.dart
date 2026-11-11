import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

const _orig = '''
/// Le nom de fichier d'un agent : minuscules, tirets.
pub fn slug(nom: &str) -> String {
    nom.trim().to_lowercase()
}

/// Le point d'entrée du navigateur.
#[cfg(target_arch = "wasm32")]
pub fn start() {
    hydrate();
}
''';

const _fn = '''
/// Le temps de lecture, en minutes.
pub fn reading_time(text: &str) -> usize {
    text.split_whitespace().count().div_ceil(200).max(1)
}''';

// Après la ligne 4 (la fin de slug) : avant le commentaire de start.
final _want = _orig.replaceFirst(
  '}\n\n/// Le point',
  '}\n$_fn\n\n/// Le point',
);

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    final p = req.url.path;
    if (p.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'site/Cargo.toml', 'type': 'blob'},
            {'path': 'site/src/lib.rs', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (p.endsWith('/contents/site/src/lib.rs')) {
      return http.Response(
        jsonEncode({
          'sha': 's',
          'content': base64.encode(utf8.encode(_orig)),
          'encoding': 'base64',
          'size': _orig.length,
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

(LlmClient, List<String>) scripted(List<String> replies) {
  var i = 0;
  final seen = <String>[];
  return (
    LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        final sent = jsonDecode(await body.bytesToString()) as Map;
        seen.add(((sent['messages'] as List).last as Map)['content'] as String);
        final r = i < replies.length
            ? replies[i++]
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
    seen,
  );
}

AgentRun runWith(LlmClient llm) => AgentRun(
  llm: llm,
  github: fake(),
  provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
  apiKey: null,
  model: 'openai',
  owner: 'max',
  repo: 'NEXORA',
  branch: 'master',
  task: 'Ajoute reading_time',
)..specs.add('déjà compris');

String action(Map<String, dynamic> args) =>
    '```json\n${jsonEncode({
      'actions': [
        {'tool': 'repo_browser.edit_file', 'args': args},
      ],
    })}\n```';

const _finish = '```json\n{"tool":"finish","args":{"summary":"fait"}}\n```';

void main() {
  AgentRun.checks = false;

  test('essai réel : un numéro de ligne seul montre les lignes autour, '
      'puis le texte envoyé est inséré après', () async {
    final (llm, seen) = scripted([
      action({'path': 'site/src/lib.rs', 'line': 4}),
      '```rust\n$_fn\n```',
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('EN ATTENTE du texte à INSÉRER après la ligne 4'));
    expect(seen[1], contains('4: }'));
    expect(seen[1], contains("6: /// Le point d'entrée du navigateur."));
    expect(seen[1], isNot(contains('il manque le texte')));
    expect(seen[2], contains('insérée(s) après la ligne 4'));
    expect(run.changes['site/src/lib.rs'], _want);
    expect(run.summary, 'fait');
  });

  test(
    'essai réel : "line" avec "old" vide et "new" : inséré tout de suite',
    () async {
      final (llm, seen) = scripted([
        action({'path': 'site/src/lib.rs', 'line': 4, 'old': '', 'new': _fn}),
        _finish,
      ]);
      final run = runWith(llm);
      await run.run();
      expect(seen[1], isNot(contains('"old" vide ajouterait')));
      expect(seen[1], contains('lignes 5 à 8'));
      expect(seen[1], contains('4: }'));
      expect(seen[1], contains('9: '));
      expect(run.changes['site/src/lib.rs'], _want);
    },
  );

  test('"insert_after" : un ajout au début ou après une ligne', () async {
    final (llm, _) = scripted([
      action({
        'path': 'site/src/lib.rs',
        'insert_after': 0,
        'new': '//! Le site.',
      }),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/src/lib.rs'], '//! Le site.\n$_orig');
  });

  test('la ligne juste après la dernière : ajouté à la fin', () async {
    final (llm, _) = scripted([
      action({'path': 'site/src/lib.rs', 'line': 11, 'old': '', 'new': _fn}),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/src/lib.rs'], '$_orig$_fn\n');
  });

  test('une ligne hors du fichier : erreur claire, rien de changé', () async {
    final (llm, seen) = scripted([
      action({'path': 'site/src/lib.rs', 'line': 40}),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('a 10 lignes, la ligne 40 n\'existe pas'));
    expect(run.changes.containsKey('site/src/lib.rs'), isFalse);
  });

  test('une autre action au lieu du texte : rien n\'est inséré', () async {
    final (llm, _) = scripted([
      action({'path': 'site/src/lib.rs', 'line': 4}),
      '```json\n{"tool":"read_file","args":{"path":"site/src/lib.rs"}}\n```',
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes.containsKey('site/src/lib.rs'), isFalse);
  });

  test('un commentaire de remplissage n\'est pas inséré', () async {
    final (llm, seen) = scripted([
      action({
        'path': 'site/src/lib.rs',
        'line': 4,
        'old': '',
        'new': 'fn a() {}\n// ... existing code',
      }),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('rien n\'est modifié'));
    expect(run.changes.containsKey('site/src/lib.rs'), isFalse);
  });

  test(
    '"line" avec un "old" non vide : il désigne toujours l\'occurrence',
    () async {
      final (llm, _) = scripted([
        action({
          'path': 'site/src/lib.rs',
          'line': 10,
          'old': '}',
          'new': '}\n// fin',
        }),
        _finish,
      ]);
      final run = runWith(llm);
      await run.run();
      expect(
        run.changes['site/src/lib.rs'],
        _orig.replaceFirst('    hydrate();\n}', '    hydrate();\n}\n// fin'),
      );
    },
  );

  test('un fichier nouveau avec "line" et "old" vide : il est créé', () async {
    final (llm, _) = scripted([
      action({'path': 'site/src/neuf.rs', 'line': 1, 'old': '', 'new': _fn}),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/src/neuf.rs'], '$_fn\n');
  });
}
