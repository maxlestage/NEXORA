import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/dart_check.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

// Le test réellement écrit par Pollinations pour « coupe les titres rapides à
// 40 caractères… Ajoute des tests unitaires » : flutter analyze refusait les
// lignes 5 et 6 (prefer_interpolation_to_compose_strings).
const _written =
    "import 'package:flutter_test/flutter_test.dart';\n"
    '\n'
    'void main() {\n'
    "  test('coupe', () {\n"
    "    final title = String.fromCharCodes(List.filled(39, 97)) + ' b';\n"
    "    expect(f(title), String.fromCharCodes(List.filled(39, 97)) + '…');\n"
    '  });\n'
    '}\n';

const _ci =
    'jobs:\n  app:\n    steps:\n'
    '      - run: flutter analyze\n';

const _options = 'include: package:flutter_lints/flutter.yaml\n';

http.Response _file(String text) => http.Response(
  jsonEncode({
    'sha': 's',
    'content': base64.encode(utf8.encode(text)),
    'encoding': 'base64',
  }),
  200,
);

GitHubApi fake({String? ci, String? options}) => GitHubApi(
  't',
  client: MockClient((req) async {
    final p = req.url.path;
    if (p.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'app/pubspec.yaml', 'type': 'blob'},
            if (ci != null)
              {'path': '.github/workflows/ci.yml', 'type': 'blob'},
            if (options != null)
              {'path': 'app/analysis_options.yaml', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (ci != null && p.endsWith('/contents/.github/workflows/ci.yml')) {
      return _file(ci);
    }
    if (options != null && p.endsWith('/contents/app/analysis_options.yaml')) {
      return _file(options);
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

AgentRun runWith(LlmClient llm, GitHubApi github) => AgentRun(
  llm: llm,
  github: github,
  provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
  apiKey: null,
  model: 'openai',
  owner: 'max',
  repo: 'NEXORA',
  branch: 'master',
  task: 'Coupe les titres rapides à 40 caractères, avec des tests unitaires',
)..specs.add('déjà compris');

String write(String content) =>
    '```json\n{"tool":"write_file","args":{"path":"app/test/title_test.dart",'
    '"content":${jsonEncode(content)}}}\n```';

void main() {
  AgentRun.checks = false;

  group('textes collés avec « + »', () {
    test('essai réel : les deux lignes du test sont signalées', () {
      expect(dartConcatProblems(_written), [
        "ligne 5 : final title = String.fromCharCodes(List.filled(39, 97)) + ' b';",
        "ligne 6 : expect(f(title), String.fromCharCodes(List.filled(39, 97)) + '…');",
      ]);
    });

    test('comme l\'analyseur : ce qu\'il refuse est signalé', () {
      for (final code in [
        "final t = x + 'c';",
        "final t = 'a' 'b' + x;",
        "final t = f(x) +\n    'y';",
        "final t = '''a''' + x;",
        "final t = 'a'.trim() + 'b';",
        "final t = x + '\$x' + x;",
        "final t = '\${x}a' + x;",
      ]) {
        expect(dartConcatProblems(code), hasLength(1), reason: code);
      }
    });

    test('ce que l\'analyseur accepte n\'est pas signalé', () {
      for (final code in [
        "final t = 'a' + 'b';",
        "final t = 'a' * 30 + ' b';",
        "final t = '  ' * --depth + '=> x';",
        "final t = x + 'b'.trim();",
        "final t = x + r'\\d';",
        "s += 'x';",
        'final n = a + b;',
        "final t = '\${a + b}';",
        "// x + 'a'",
        "final t = 'x + \\'a\\'';",
      ]) {
        expect(dartConcatProblems(code), isEmpty, reason: code);
      }
    });

    test('seules les lignes de l\'agent comptent', () {
      expect(
        AgentRun.dartConcatHint('app/test/t.dart', _written, before: _written),
        isNull,
      );
      final hint = AgentRun.dartConcatHint('app/test/t.dart', _written)!;
      expect(hint, contains('flutter analyze'));
      expect(hint, contains('ligne 5'));
      expect(AgentRun.dartConcatHint('src/main.rs', _written), isNull);
    });

    test('quelle CI refuse les remarques de l\'analyseur', () {
      expect(
        AgentRun.dartAnalyzeRefusesInfos('- run: flutter analyze'),
        isTrue,
      );
      expect(
        AgentRun.dartAnalyzeRefusesInfos('- run: dart analyze --fatal-infos'),
        isTrue,
      );
      expect(AgentRun.dartAnalyzeRefusesInfos('- run: dart analyze'), isFalse);
      expect(
        AgentRun.dartAnalyzeRefusesInfos(
          '- run: flutter analyze --no-fatal-infos',
        ),
        isFalse,
      );
    });

    test('dans une session : l\'agent est prévenu dès l\'écriture', () async {
      final (llm, seen) = scripted([write(_written)]);
      await runWith(llm, fake(ci: _ci, options: _options)).run();
      expect(seen[1], contains('enregistré en brouillon'));
      expect(seen[1], contains('prefer_interpolation_to_compose_strings'));
      expect(seen[1], contains('ligne 5'));
    });

    test('sans flutter analyze en CI, ou règle coupée : rien', () async {
      var (llm, seen) = scripted([write(_written)]);
      await runWith(llm, fake(options: _options)).run();
      expect(seen[1], contains('enregistré en brouillon'));
      expect(seen[1], isNot(contains('prefer_interpolation')));

      (llm, seen) = scripted([write(_written)]);
      await runWith(
        llm,
        fake(
          ci: _ci,
          options:
              '$_options'
              'linter:\n  rules:\n'
              '    prefer_interpolation_to_compose_strings: false\n',
        ),
      ).run();
      expect(seen[1], isNot(contains('prefer_interpolation')));
    });
  });
}
