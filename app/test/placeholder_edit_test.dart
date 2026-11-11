import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse sse(String text) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

const mainRs = '''
async fn robots(_req: Request) -> String {
    "User-agent: *".to_string()
}

async fn telecharger(_req: Request) -> Page {
    let plateformes = section().class("section");
    page("Télécharger", vec![plateformes.into()])
}
''';

void main() {
  AgentRun.checks = false;

  group('commentaire qui tient la place du code existant', () {
    test('repéré dans le texte ajouté', () {
      for (final l in [
        '    // ... existing code',
        '// …',
        '    // ... other routes',
        '// existing code unchanged',
        '// rest of the file',
        '  # ... rest of the tests',
        '/* ... */',
        '<!-- ... -->',
        '// reste du code inchangé',
        '// ... code existant',
        '    // (existing tests here)',
      ]) {
        expect(
          placeholderLine('fn a() {\n$l\n}', 'fn a() {', ''),
          l,
          reason: l,
        );
      }
    });

    test('les vrais commentaires ne sont pas visés', () {
      for (final l in [
        '// Lit la première version de nouveautes.md.',
        '/// ...',
        '//! ...',
        '#[cfg(test)]',
        '# Previous versions',
        '// Other platforms are handled below.',
        '// The existing value is kept when the key is missing.',
        "    let rest = '...';",
        '    // TODO',
      ]) {
        expect(placeholderLine('fn a() {\n$l\n}', '', ''), isNull, reason: l);
      }
    });

    test('déjà dans le fichier ou dans old : gardé tel quel', () {
      const line = '    // ... existing code';
      expect(placeholderLine('x\n$line', line, ''), isNull);
      expect(placeholderLine('x\n$line', 'x', 'a\n$line\nb'), isNull);
    });

    test('cas réel : la modification est refusée, le fichier reste intact', () async {
      final replies = [
        // Essai réel (Pollinations) : old = la première ligne de telecharger,
        // new = cette ligne, « // ... existing code », « } » et une nouvelle
        // fonction. Le corps de telecharger restait orphelin.
        '```json\n${jsonEncode({
          'tool': 'edit_file',
          'args': {'path': 'site/src/main.rs', 'old': 'async fn telecharger(_req: Request) -> Page {', 'new': 'async fn telecharger(_req: Request) -> Page {\n'
              '    // ... existing code\n'
              '}\n\n'
              'async fn version(_req: Request) -> String {\n'
              '    "2.2.90".to_string()\n'
              '}'},
        })}\n```',
        '```json\n${jsonEncode({
          'tool': 'edit_file',
          'args': {'path': 'site/src/main.rs', 'old': 'async fn telecharger(_req: Request) -> Page {', 'new': 'async fn version(_req: Request) -> String {\n'
              '    "2.2.90".to_string()\n'
              '}\n\n'
              'async fn telecharger(_req: Request) -> Page {'},
        })}\n```',
        '```json\n${jsonEncode({
          'tool': 'finish',
          'args': {'summary': 'Route /version ajoutée'},
        })}\n```',
      ];
      var i = 0;
      final requests = <String>[];
      final run = AgentRun(
        llm: LlmClient(
          clientFactory: () => MockClient.streaming((req, body) async {
            requests.add(await body.bytesToString());
            return sse(replies[i++]);
          }),
        ),
        github: GitHubApi(
          't',
          client: MockClient((req) async {
            final p = req.url.path;
            if (p.contains('/git/trees/')) {
              return http.Response(
                jsonEncode({
                  'tree': [
                    {'path': 'site/src/main.rs', 'type': 'blob'},
                  ],
                }),
                200,
              );
            }
            if (p.endsWith('/contents/site/src/main.rs')) {
              return http.Response(
                jsonEncode({
                  'sha': 's',
                  'content': base64.encode(utf8.encode(mainRs)),
                  'encoding': 'base64',
                  'size': mainRs.length,
                }),
                200,
              );
            }
            return http.Response('{"message":"Not Found"}', 404);
          }),
        ),
        provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
        apiKey: 'k',
        model: 'm',
        owner: 'max',
        repo: 'NEXORA',
        branch: 'master',
        task: 'Ajoute une route /version',
      );
      await run.run();
      expect(run.summary, 'Route /version ajoutée');
      // Le refus explique quoi faire au lieu du commentaire.
      expect(requests[1], contains('// ... existing code'));
      expect(requests[1], contains('tient la place de code existant'));
      final after = run.changes['site/src/main.rs']!;
      expect(after, isNot(contains('existing code')));
      expect(after, contains('async fn version'));
      // Le corps de telecharger est toujours à sa place.
      expect(
        after,
        contains(
          'async fn telecharger(_req: Request) -> Page {\n'
          '    let plateformes',
        ),
      );
    });
  });
}
