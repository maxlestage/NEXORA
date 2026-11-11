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
    let mut out = String::new();
    for c in nom.trim().chars() {
        let c = match c {
            'é' | 'è' => 'e',
            'ç' => 'c',
            c => c.to_ascii_lowercase(),
        };
        out.push(c);
    }
    out
}
''';

// Les lignes 6 et 7 (les branches accentuées), récrites.
const _arms = '''            'É' | 'é' | 'è' => 'e',
            'Ç' | 'ç' => 'c',''';

final _want = _orig.replaceFirst('''            'é' | 'è' => 'e',
            'ç' => 'c',''', _arms);

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
  task: 'slug() doit gérer les majuscules accentuées',
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

  test('essai réel : une plage seule montre les lignes, '
      'puis le texte envoyé les remplace', () async {
    final (llm, seen) = scripted([
      action({'path': 'site/src/lib.rs', 'line_start': 6, 'line_end': 7}),
      '```rust\n$_arms\n```',
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('EN ATTENTE du nouveau texte des lignes 6 à 7'));
    expect(seen[1], contains("6:             'é' | 'è' => 'e',"));
    expect(seen[1], contains("7:             'ç' => 'c',"));
    expect(seen[1], isNot(contains('il manque le texte')));
    expect(seen[2], contains('modifié en brouillon'));
    expect(run.changes['site/src/lib.rs'], _want);
    expect(run.summary, 'fait');
  });

  test('une plage avec "new" (sans "old") remplace ces lignes', () async {
    final (llm, seen) = scripted([
      action({
        'path': 'site/src/lib.rs',
        'start_line': 6,
        'end_line': 7,
        'new': _arms,
      }),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('modifié en brouillon'));
    expect(run.changes['site/src/lib.rs'], _want);
  });

  test('une plage et un seul bloc de code après le JSON', () async {
    final (llm, _) = scripted([
      '${action({'path': 'site/src/lib.rs', 'lines': '6-7'})}\n'
          '```rust\n$_arms\n```',
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/src/lib.rs'], _want);
  });

  test('old et new donnés : la plage ne change rien', () async {
    final (llm, _) = scripted([
      action({
        'path': 'site/src/lib.rs',
        'line_start': 1,
        'line_end': 200,
        'old': "            'ç' => 'c',",
        'new': "            'Ç' | 'ç' => 'c',",
      }),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(
      run.changes['site/src/lib.rs'],
      _orig.replaceFirst("'ç' => 'c'", "'Ç' | 'ç' => 'c'"),
    );
  });

  test('une plage hors du fichier : erreur claire, rien de changé', () async {
    final (llm, seen) = scripted([
      action({'path': 'site/src/lib.rs', 'line_start': 404, 'line_end': 420}),
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('a 13 lignes, la ligne 404 n\'existe pas'));
    expect(run.changes.containsKey('site/src/lib.rs'), isFalse);
  });

  test('une autre action au lieu du texte : rien n\'est remplacé', () async {
    final (llm, _) = scripted([
      action({'path': 'site/src/lib.rs', 'line_start': 6, 'line_end': 7}),
      '```json\n{"tool":"read_file","args":{"path":"site/src/lib.rs"}}\n```',
      _finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes.containsKey('site/src/lib.rs'), isFalse);
  });

  test('sans plage, le message d\'origine reste', () async {
    final (llm, seen) = scripted([
      action({'path': 'site/src/lib.rs'}),
      _finish,
    ]);
    await runWith(llm).run();
    expect(seen[1], contains('il manque le texte'));
  });
}
