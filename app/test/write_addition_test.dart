import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Un vrai fichier Dart assez long (comme llm_parsers.dart, 19 000 caractères).
final _long = [
  "import 'dart:convert';",
  '',
  for (var i = 0; i < 40; i++) ...[
    '/// Lit le champ $i d\'une réponse.',
    'String? field$i(Map<String, dynamic> j) {',
    "  final v = j['field$i'];",
    '  return v is String ? v : jsonEncode(v);',
    '}',
    '',
  ],
].join('\n');

/// Ce qu'a écrit Pollinations en essai réel : seulement la fonction ajoutée.
const _onlyNew = '''
String shortModelName(String id) {
  final idx = id.lastIndexOf('/');
  if (idx == -1) return id;
  return id.substring(idx + 1);
}
''';

GitHubApi _fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'lib/parsers.dart', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (req.url.path.endsWith('/contents/lib/parsers.dart')) {
      return http.Response(
        jsonEncode({
          'sha': 's',
          'content': base64.encode(utf8.encode(_long)),
          'encoding': 'base64',
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

(AgentRun, List<String>) _run(List<String> replies) {
  var i = 0;
  final seen = <String>[];
  final llm = LlmClient(
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
  );
  final run = AgentRun(
    llm: llm,
    github: _fake(),
    provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
    apiKey: null,
    model: 'openai',
    owner: 'max',
    repo: 'app',
    branch: 'main',
    task: 'Ajoute shortModelName dans lib/parsers.dart',
  )..specs.add('déjà compris');
  return (run, seen);
}

String _write(String content, {Map<String, Object> extra = const {}}) =>
    '```json\n${jsonEncode({
      'tool': 'write_file',
      'args': {'path': 'lib/parsers.dart', 'content': content, ...extra},
    })}\n```';

void main() {
  AgentRun.checks = false;

  group('pureAddition', () {
    test('essai réel : une fonction nouvelle seule est un ajout', () {
      expect(pureAddition('lib/parsers.dart', _long, _onlyNew), isTrue);
    });

    test('un module de tests Rust (use en retrait) est un ajout', () {
      const rs =
          '#[cfg(test)]\nmod tests {\n    use super::*;\n\n'
          '    #[test]\n    fn compte() {\n'
          '        assert_eq!(word_count("a b"), 2);\n    }\n}\n';
      final lib = _long.replaceAll('String?', 'fn').replaceAll("'", '"');
      expect(pureAddition('src/lib.rs', lib, rs), isTrue);
    });

    test('un import au premier niveau : une réécriture, pas un ajout', () {
      expect(
        pureAddition(
          'lib/parsers.dart',
          _long,
          "import 'package:x/x.dart';\n$_onlyNew",
        ),
        isFalse,
      );
    });

    test('du code en retrait (un morceau de fonction) n\'est pas visé', () {
      expect(
        pureAddition(
          'lib/parsers.dart',
          _long,
          "  final v = id.trim();\n  return v.split('/').last;\n",
        ),
        isFalse,
      );
    });

    test('du code qui reprend des lignes du fichier n\'est pas visé', () {
      expect(
        pureAddition(
          'lib/parsers.dart',
          _long,
          "String? field3(Map<String, dynamic> j) {\n  final v = j['x'];\n"
              '  return null;\n}\n',
        ),
        isFalse,
      );
    });

    test('la documentation n\'est pas visée', () {
      expect(
        pureAddition('README.md', 'x\n' * 4000, '## Tests\n\ncargo test\n'),
        isFalse,
      );
    });

    test('un contenu presque aussi long que le fichier n\'est pas visé', () {
      expect(pureAddition('lib/a.dart', 'x\n' * 100, _onlyNew * 2), isFalse);
    });
  });

  test('essai réel : write_file avec seulement la fonction nouvelle sur un '
      'long fichier : ajoutée à la fin, rien n\'est perdu', () async {
    final (run, seen) = _run([_write(_onlyNew)]);
    await run.run();
    final draft = run.changes['lib/parsers.dart']!;
    expect(draft, startsWith(_long.trimRight()));
    expect(draft, contains('String shortModelName(String id) {'));
    expect(draft.trimRight(), endsWith('return id.substring(idx + 1);\n}'));
    expect(seen[1], contains('c\'est un AJOUT'));
    expect(seen[1], isNot(contains('la fin du fichier serait perdue')));
  });

  test('avec un import en tête : toujours refusé, le fichier intact', () async {
    final (run, seen) = _run([_write("import 'package:x/x.dart';\n$_onlyNew")]);
    await run.run();
    expect(run.changes.containsKey('lib/parsers.dart'), isFalse);
    expect(seen[1], contains('ERREUR'));
  });

  test('"force": true remplace toujours vraiment le fichier', () async {
    final (run, _) = _run([
      _write(_onlyNew, extra: {'force': true}),
    ]);
    await run.run();
    expect(run.changes['lib/parsers.dart'], isNot(contains('field3')));
    expect(run.changes['lib/parsers.dart'], contains('shortModelName'));
  });
}
