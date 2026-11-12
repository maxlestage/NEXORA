import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/dart_check.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

// La ligne réellement écrite par Pollinations pour « ajoute un getter
// totalWords » : 86 caractères, refusée par dart format en CI.
const _long =
    '      final words = m.content.split(RegExp(r\'\\s+\'))'
    '.where((w) => w.isNotEmpty).length;';

const _written =
    'class Conversation {\n'
    '  final List<String> messages = [];\n'
    '  int get totalWords {\n'
    '    return messages.fold(0, (sum, m) {\n'
    '$_long\n'
    '      return sum + words;\n'
    '    });\n'
    '  }\n'
    '}\n';

const _ci =
    'jobs:\n  app:\n    steps:\n'
    '      - run: dart format --output=none --set-exit-if-changed lib test\n';

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
  task: 'Ajoute un getter totalWords à Conversation',
)..specs.add('déjà compris');

String write(String content) =>
    '```json\n{"tool":"write_file","args":{"path":"app/lib/chat.dart",'
    '"content":${jsonEncode(content)}}}\n```';

void main() {
  AgentRun.checks = false;

  group('lignes trop longues pour dart format', () {
    test('essai réel : la ligne de 86 caractères est signalée', () {
      final hint = AgentRun.dartFormatHint('app/lib/chat.dart', _written)!;
      expect(hint, contains('ligne 5 (86 caractères)'));
      expect(hint, contains('final words = m.content.split'));
      expect(hint, contains('dart format'));
    });

    test('ce que dart format laisse long n\'est pas signalé', () {
      final text = [
        "import 'package:nexora/un/chemin/tres/long/pour/depasser/la/limite/de/quatre/vingts.dart';",
        '  // Un commentaire très long qui dépasse largement les quatre-vingts caractères permis.',
        "    hintText: 'Ex. : ajoute un mode sombre à l\\'app et mets à jour le README',",
        "          ? 'Pull request ouverte : CI puis fusion en cours, merci de patienter'",
        '  final a = f(1); // un commentaire en fin de ligne qui est vraiment très très long',
        "  const t = '''",
        'Un texte sur plusieurs lignes, long, très long, bien plus long que quatre-vingts.',
        "''';",
        '// dart format off',
        '  final List<int> valeurs = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];',
        '// dart format on',
      ].join('\n');
      expect(AgentRun.dartFormatHint('lib/a.dart', text), isNull);
    });

    test('seules les lignes de l\'agent comptent, à la largeur du projet', () {
      expect(
        AgentRun.dartFormatHint(
          'app/lib/chat.dart',
          _written,
          before: _written,
        ),
        isNull,
      );
      expect(
        AgentRun.dartFormatHint('app/lib/chat.dart', _written, width: 100),
        isNull,
      );
      expect(AgentRun.dartFormatHint('src/main.rs', _written), isNull);
    });

    test(
      'CI avec dart format : prévenu dès l\'écriture, une seule fois',
      () async {
        final (llm, seen) = scripted([write(_written), write(_written)]);
        await runWith(llm, fake(ci: _ci)).run();
        expect(seen[1], contains('enregistré en brouillon'));
        expect(seen[1], contains('ligne 5 (86 caractères)'));
        // La même écriture refaite n'est pas refaite : sous le résultat
        // précédent, la relance ne répète pas l'alerte.
        expect(
          seen[2].split(AgentRun.repeatMark).last,
          isNot(contains('caractères au plus par ligne')),
        );
      },
    );

    test('pas de vérification du format en CI : rien n\'est dit', () async {
      final (llm, seen) = scripted([write(_written)]);
      await runWith(llm, fake()).run();
      expect(seen[1], contains('enregistré en brouillon'));
      expect(seen[1], isNot(contains('caractères au plus par ligne')));
    });

    test('la largeur de analysis_options.yaml est respectée', () async {
      final (llm, seen) = scripted([write(_written)]);
      await runWith(
        llm,
        fake(ci: _ci, options: 'formatter:\n  page_width: 100\n'),
      ).run();
      expect(seen[1], isNot(contains('caractères au plus par ligne')));
    });
  });

  group('indentation refusée par dart format', () {
    // Le texte réellement écrit par Pollinations pour « renvoie le titre
    // d'une page d'erreur HTML dans errorFromBody » (essai réel).
    const bad =
        'String errorFromBody(String body) {\n'
        '  final t = body.trim();\n'
        "  if (t.startsWith('<html')) {\n"
        '    final titleMatch = RegExp(\n'
        "    r'<title>(.*?)</title>',\n"
        '    caseSensitive: false,\n'
        '    dotAll: true,\n'
        '  ).firstMatch(t);\n'
        '    if (titleMatch != null) return titleMatch.group(1)!;\n'
        '  }\n'
        '  return t;\n'
        '}\n';
    const good =
        'String errorFromBody(String body) {\n'
        '  final t = body.trim();\n'
        "  if (t.startsWith('<html')) {\n"
        '    final titleMatch = RegExp(\n'
        "      r'<title>(.*?)</title>',\n"
        '      caseSensitive: false,\n'
        '      dotAll: true,\n'
        '    ).firstMatch(t);\n'
        '    if (titleMatch != null) return titleMatch.group(1)!;\n'
        '  }\n'
        '  return t;\n'
        '}\n';

    test('essai réel : arguments et fermeture mal indentés', () {
      final found = dartIndentProblems(bad);
      expect(found, hasLength(2));
      expect(found[0], startsWith('ligne 5 : 4 espaces'));
      expect(found[0], contains('il en faut 6'));
      expect(found[1], startsWith('ligne 8 : « ) »'));
      expect(found[1], contains('4 espaces (et non 2)'));
      expect(dartIndentProblems(good), isEmpty);
    });

    test('ce que dart format écrit ainsi n\'est pas signalé', () {
      const code =
          'void f(\n'
          '  String q, {\n'
          '  required int n,\n'
          '}) {\n'
          '  final a = ok\n'
          '      ? g(\n'
          '          1,\n'
          '        )\n'
          '      : 2;\n'
          '  final b = list\n'
          '      .where(\n'
          '        (x) => x > 1,\n'
          '      )\n'
          '      .toList();\n'
          "  test('un long titre '\n"
          "      'sur deux lignes', (\n"
          '    WidgetTester tester,\n'
          '  ) async {});\n'
          '  if ( // commentaire\n'
          '  a) {}\n'
          '  final c = h(\n'
          "    '''\n"
          'texte\n'
          "''',\n"
          '  );\n'
          '  final d = [\n'
          '    1,\n'
          '  ];\n'
          '}\n';
      expect(dartIndentProblems(code), isEmpty);
    });

    test('les lignes du fichier d\'origine ne sont pas visées', () {
      final old = bad.split('\n').toSet();
      expect(dartIndentProblems(bad, old: old), isEmpty);
      expect(
        AgentRun.dartIndentHint('app/lib/a.dart', bad, before: bad),
        isNull,
      );
      expect(AgentRun.dartIndentHint('src/main.rs', bad), isNull);
    });

    test('CI avec dart format : prévenu dès l\'écriture', () async {
      final (llm, seen) = scripted([write(bad)]);
      await runWith(llm, fake(ci: _ci)).run();
      expect(seen[1], contains('enregistré en brouillon'));
      expect(seen[1], contains('mal indenté'));
      expect(seen[1], contains('ligne 8 : « ) »'));
    });

    test('pas de vérification du format en CI : rien n\'est dit', () async {
      final (llm, seen) = scripted([write(bad)]);
      await runWith(llm, fake()).run();
      expect(seen[1], contains('enregistré en brouillon'));
      expect(seen[1], isNot(contains('mal indenté')));
    });
  });
}
