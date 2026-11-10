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

void main() {
  // Les tests obligatoires et la relecture finale ont leurs propres tests.
  AgentRun.checks = false;
  // Un style.css de plus de 49 000 caractères, comme celui de STRATYX.
  final css = StringBuffer();
  for (var i = 0; i < 1800; i++) {
    css.writeln('.regle-$i { margin: 0 ${i}px; color: #123456; }');
  }
  css.writeln('.atelier { display: grid; grid-template-columns: 320px 1fr; }');
  css.writeln('/* FIN DU FICHIER */');
  final big = css.toString();

  GitHubApi github() => GitHubApi(
    't',
    client: MockClient((req) async {
      final p = req.url.path;
      if (p.contains('/git/trees/')) {
        return http.Response(
          jsonEncode({
            'tree': [
              {'path': 'site/public/style.css', 'type': 'blob'},
            ],
          }),
          200,
        );
      }
      if (p.endsWith('/contents/site/public/style.css')) {
        return http.Response(
          jsonEncode({
            'sha': 's',
            'content': base64.encode(utf8.encode(big)),
            'encoding': 'base64',
            'size': big.length,
          }),
          200,
        );
      }
      return http.Response('{"message":"Not Found"}', 404);
    }),
  );

  test(
    'long fichier : lu par plages, cherché, modifié sans perdre la fin',
    () async {
      expect(big.length, greaterThan(49000));
      final replies = [
        '```json\n${jsonEncode({
          'actions': [
            {
              'tool': 'read_file',
              'args': {'path': 'site/public/style.css'},
            },
            {
              'tool': 'find_in_file',
              'args': {'path': 'site/public/style.css', 'pattern': 'atelier'},
            },
          ],
        })}\n```',
        '```json\n${jsonEncode({
              'thought': 'Colonne fixe trop large sur mobile',
              'tool': 'edit_file',
              'args': {'path': 'site/public/style.css'},
            })}\n```\n'
            '```css\n.atelier { display: grid; grid-template-columns: 320px 1fr; }\n```\n'
            '```css\n.atelier { display: grid; grid-template-columns: minmax(0, 320px) 1fr; }\n```',
        '```json\n${jsonEncode({
          'tool': 'finish',
          'args': {'summary': 'Défilement corrigé'},
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
        github: github(),
        provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
        apiKey: 'k',
        model: 'm',
        owner: 'max',
        repo: 'STRATYX',
        branch: 'main',
        task: 'Corrige le défilement horizontal',
      );
      await run.run();
      expect(run.summary, 'Défilement corrigé');
      final after = run.changes['site/public/style.css']!;
      expect(after, contains('minmax(0, 320px)'));
      expect(after, contains('/* FIN DU FICHIER */'));
      expect(after, contains('.regle-0 '));
      expect(after.length, greaterThan(49000));
      // La lecture d'un long fichier indique comment lire la suite.
      expect(requests[1], contains('Lis la suite'));
      expect(requests[1], contains('1801: .atelier'));
    },
  );

  test(
    'modification ciblée : passage unique, espaces de fin tolérés',
    () async {
      final run = AgentRun(
        llm: LlmClient(),
        github: github(),
        provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
        apiKey: 'k',
        model: 'm',
        owner: 'max',
        repo: 'STRATYX',
        branch: 'main',
        task: 't',
      );
      run.originals['site/public/style.css'] = big;
      expect(applyEdit(big, '.atelier', '.x', all: false).$1, isNotNull);
      expect(applyEdit('a\na\n', 'a', 'b').$1, isNull); // pas unique
      expect(applyEdit('a  \nb\n', 'a\nb', 'c').$1, 'c\n'); // espaces de fin
    },
  );
}
