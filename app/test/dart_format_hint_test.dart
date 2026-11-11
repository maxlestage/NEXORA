import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
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
        expect(seen[2], isNot(contains('caractères au plus par ligne')));
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
}
