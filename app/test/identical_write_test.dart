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

  test('sameText ignore les fins de ligne, pas le contenu', () {
    expect(sameText('a\nb\n', 'a\r\nb'), isTrue);
    expect(sameText('a\nb\n', 'a\nb\n\n'), isTrue);
    expect(sameText('a\nb\n', 'a\nc\n'), isFalse);
    expect(sameText('a  \n', 'a\n'), isFalse);
    expect(sameText('a\n', null), isFalse);
  });

  test('le même fichier réécrit à l\'identique : « Déjà fait », le '
      'brouillon reste le même', () async {
    // Essai réel (Pollinations) : app/test/diff_test.dart réécrit deux fois de
    // suite avec le même contenu, lu « OK, enregistré » les deux fois.
    const call =
        '```json\n{"tool":"write_file","args":{"path":"site/test.md",'
        '"content":"# Titre\\nUn point\\n"}}\n```';
    // Une lecture entre les deux, comme dans l'essai.
    final (llm, seen) = scripted([
      call,
      '```json\n{"tool":"read_file","args":{"path":"site/notes.md"}}\n```',
      call,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/test.md'], '# Titre\nUn point\n');
    expect(seen[1], contains('enregistré en brouillon'));
    expect(seen[3], contains('Déjà fait'));
    expect(seen[3], contains('appelle finish'));
    expect(seen[3], isNot(contains('enregistré en brouillon')));
  });

  test('un contenu identique au fichier du dépôt : aucun brouillon', () async {
    final call =
        '```json\n{"tool":"write_file","args":{"path":"site/notes.md",'
        '"content":${jsonEncode('$_notes\n')}}}\n```';
    final (llm, seen) = scripted([call]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes.containsKey('site/notes.md'), isFalse);
    expect(seen[1], contains('identique à site/notes.md'));
  });

  test('un vrai changement est toujours écrit', () async {
    const a =
        '```json\n{"tool":"write_file","args":{"path":"site/test.md",'
        '"content":"v1"}}\n```';
    const b =
        '```json\n{"tool":"write_file","args":{"path":"site/test.md",'
        '"content":"v2"}}\n```';
    final (llm, seen) = scripted([a, b]);
    final run = runWith(llm);
    await run.run();
    expect(run.changes['site/test.md'], 'v2\n');
    expect(seen[2], contains('enregistré en brouillon'));
  });
}
