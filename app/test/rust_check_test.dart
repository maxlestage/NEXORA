import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/rust_check.dart';

// slug() du site, tel qu'il est sur GitHub.
const _orig = '''
/// Le nom de fichier d'un agent : minuscules, tirets.
pub fn slug(nom: &str) -> String {
    let mut out = String::new();
    for c in nom.trim().chars() {
        let c = match c {
            'à' | 'â' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'ç' => 'c',
            c => c.to_ascii_lowercase(),
        };
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') && !out.is_empty() {
            out.push('-');
        }
    }
    out
}
''';

// Essai réel (Pollinations, « slug() ignore les majuscules accentuées ») :
// « old » ne couvrait que le début du match, « new » le récrivait en entier.
// Les anciennes branches restaient derrière, avec une accolade de trop.
const _old = '''        let c = match c {
            'à' | 'â' | 'ä' => 'a',''';
const _new = '''        let c = match c {
            'À' | 'Â' | 'Ä' | 'à' | 'â' | 'ä' => 'a',
            'É' | 'È' | 'Ê' | 'Ë' | 'é' | 'è' | 'ê' | 'ë' => 'e',
            'Ç' | 'ç' => 'c',
            c => c.to_ascii_lowercase(),
        }''';
const _goodOld = '''            'é' | 'è' | 'ê' | 'ë' => 'e',
            'ç' => 'c',''';
const _goodNew = '''            'É' | 'é' | 'è' | 'ê' | 'ë' => 'e',
            'Ç' | 'ç' => 'c',''';

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
  task: 'Dans le site, slug() ignore les majuscules accentuées',
)..specs.add('déjà compris');

String edit(String old, String now) =>
    '```json\n${jsonEncode({
      'tool': 'edit_file',
      'args': {'path': 'site/src/lib.rs', 'old': old, 'new': now},
    })}\n```';

void main() {
  AgentRun.checks = false;

  test('le Rust valide n\'est jamais signalé', () {
    expect(rustSyntaxError(_orig), isNull);
    for (final ok in [
      "fn f<'a>(x: &'a str) -> &'a str { x }",
      "let c = '{'; let d = '}'; let e = '\\''; let f = '\\\\';",
      "let u = '\\u{e9}'; let b = b'['; let g = '🦀';",
      'let s = "a { b ( [ \\" c";',
      'let r = r#"brut "{" (["#; let q = br"x}";',
      'let m = r##"un "# dedans { "##;',
      "'outer: loop { break 'outer; }",
      '// une accolade { dans un commentaire\nfn g() {}',
      '/* imbriqué /* { */ toujours ( */\nfn h() {}',
      'let t = "sur\nplusieurs { lignes";',
      'fn r#type() {}',
      'fn k() {} static S: &str = "\\\\";',
    ]) {
      expect(rustSyntaxError(ok), isNull, reason: ok);
    }
  });

  test('les erreurs certaines sont repérées, avec la ligne', () {
    final broken = _orig.replaceFirst(_old, _new);
    final e = rustSyntaxError(broken)!;
    expect(e, contains('ferme quelque chose qui n\'a jamais été ouvert'));
    expect(e, startsWith('ligne 22 '));
    // La première branche restée derrière la « } » ajoutée trop tôt.
    expect(e, contains('le décalage commence sans doute ligne 11 (« \'é\''));
    expect(e, contains('la « } » de la ligne 10 juste avant'));
    expect(rustSyntaxError('fn f() {\n    g(1];\n}\n'), contains('« ] »'));
    expect(rustSyntaxError('fn f() {\n    g(1);\n'), contains('jamais fermé'));
    expect(rustSyntaxError('let s = "sans fin;\n'), contains('chaîne'));
    expect(rustSyntaxError('let s = r#"sans fin";\n'), contains('"#'));
  });

  test('Dart et Rust : chacun avec sa relecture', () {
    final broken = _orig.replaceFirst(_old, _new);
    expect(AgentRun.syntaxHint('site/src/lib.rs', _orig), isNull);
    expect(
      AgentRun.syntaxHint('site/src/lib.rs', broken),
      contains('site/src/lib.rs ne compilera pas, ligne 22'),
    );
    expect(AgentRun.syntaxHint('notes.md', broken), isNull);
    expect(AgentRun.dartSyntaxHint('site/src/lib.rs', broken), isNull);
  });

  test('edit_file qui casse le Rust : prévenu tout de suite, '
      'et finish refusé tant que ce n\'est pas corrigé', () async {
    final (llm, seen) = scripted([
      edit(_old, _new),
      '```json\n{"tool":"finish","args":{"summary":"fait"}}\n```',
      '```json\n{"tool":"write_file","args":{"path":"site/src/lib.rs",'
          '"content":${jsonEncode(_orig.replaceFirst(_goodOld, _goodNew))}}}'
          '\n```',
      '```json\n{"tool":"finish","args":{"summary":"corrigé"}}\n```',
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], contains('modifié en brouillon'));
    expect(seen[1], contains('site/src/lib.rs ne compilera pas, ligne 22'));
    expect(seen[2], contains('Tu ne peux pas terminer'));
    expect(run.summary, 'corrigé');
    expect(rustSyntaxError(run.changes['site/src/lib.rs']!), isNull);
  });

  test('une modification correcte ne déclenche rien', () async {
    final (llm, seen) = scripted([
      edit(_goodOld, _goodNew),
      '```json\n{"tool":"finish","args":{"summary":"fait"}}\n```',
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[1], isNot(contains('ne compilera pas')));
    expect(seen.any((s) => s.contains('Tu ne peux pas terminer')), isFalse);
    expect(run.summary, 'fait');
  });
}
