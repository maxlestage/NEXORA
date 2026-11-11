import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

final _notes = [for (var i = 1; i <= 300; i++) '- Point numéro $i'].join('\n');

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'site/notes.md', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (req.url.path.endsWith('/contents/site/notes.md')) {
      return http.Response(
        jsonEncode({
          'sha': 's',
          'content': base64.encode(utf8.encode('$_notes\n')),
          'encoding': 'base64',
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
  repo: 'site',
  branch: 'main',
  task: 'Ajoute un lien à la fin des notes',
)..specs.add('déjà compris');

void main() {
  AgentRun.checks = false;

  test('les façons de demander un ajout à la fin', () {
    expect(AgentRun.appendMode({'at_end': true}), isTrue);
    expect(AgentRun.appendMode({'append': 'true'}), isTrue);
    expect(AgentRun.appendMode({'mode': 'append'}), isTrue);
    expect(AgentRun.appendMode({'path': 'a.md'}), isFalse);
    expect(AgentRun.appendMode({'mode': 'overwrite'}), isFalse);
  });

  test('write_file « at_end » sans contenu : seul l\'ajout est demandé, puis '
      'ajouté à la fin, sans rien perdre', () async {
    // Réponse réelle de Pollinations : write_file avec at_end, sans contenu.
    final (llm, seen) = scripted([
      '```json\n{"actions":[{"tool":"repo_browser.write_file","args":'
          '{"path":"site/notes.md","at_end":true}}]}\n```',
      '```markdown\n[Retour en haut](#)\n```',
    ]);
    final run = runWith(llm);
    await run.run();
    final draft = run.changes['site/notes.md']!;
    expect(draft, '$_notes\n[Retour en haut](#)\n');
    expect(seen[1], contains('texte à AJOUTER'));
    expect(seen[1], isNot(contains('contenu COMPLET')));
    expect(seen[2], contains('texte ajouté à la fin'));
  });

  test(
    'write_file « append » avec son contenu : ajouté une seule fois',
    () async {
      const call =
          '```json\n{"tool":"write_file","args":{"path":"site/notes.md",'
          '"mode":"append","content":"[Retour en haut](#)"}}\n```';
      final (llm, seen) = scripted([call, call]);
      final run = runWith(llm);
      await run.run();
      expect(run.changes['site/notes.md'], '$_notes\n[Retour en haut](#)\n');
      expect(run.changes['site/notes.md']!.split('Retour en haut').length, 2);
    },
  );

  test(
    'write_file sans contenu sur un long fichier : edit_file est proposé',
    () async {
      final (llm, seen) = scripted([
        '```json\n{"tool":"write_file","args":{"path":"site/notes.md"}}\n```',
      ]);
      final run = runWith(llm);
      await run.run();
      expect(seen[1], contains('utilise plutôt edit_file'));
      expect(seen[1], contains('"at_end": true'));
    },
  );
}
