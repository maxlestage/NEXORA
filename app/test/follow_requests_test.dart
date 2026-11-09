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

String act(String tool, Map args, [String? content]) =>
    '```json\n${jsonEncode({'thought': '…', 'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```\n$content\n```'}';

void main() {
  late List<String> requests;

  AgentRun build(List<String> replies) {
    var i = 0;
    requests = [];
    return AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          requests.add(await body.bytesToString());
          return sse(replies[i++]);
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'site',
      branch: 'main',
      task: 'Mets le titre en rouge',
    );
  }

  test(
    'les demandes sont redonnées à chaque étape, la dernière prime',
    () async {
      final run = build([
        act('write_file', {'path': 'a.css'}, 'h1{color:red}'),
        act('finish', {'summary': 'Titre rouge'}),
        act('write_file', {'path': 'a.css'}, 'h1{color:blue}'),
        act('finish', {'summary': 'Titre bleu'}),
      ]);
      await run.run();
      await run.run(followUp: 'Finalement en bleu, pas en rouge');
      expect(run.changes['a.css'], contains('color:blue'));
      // Chaque requête au modèle contient toutes les demandes et les règles.
      final last = requests.last;
      expect(last, contains('DEMANDES DE L'));
      expect(last, contains('Mets le titre en rouge'));
      expect(last, contains('Finalement en bleu, pas en rouge'));
      expect(last, contains('la plus r'));
      expect(last, contains('EXACTEMENT'));
      expect(run.requests, [
        'Mets le titre en rouge',
        'Finalement en bleu, pas en rouge',
      ]);
    },
  );

  test(
    'terminer sans rien faire pour la demande est refusé une fois',
    () async {
      final run = build([
        act('write_file', {'path': 'a.css'}, 'h1{color:red}'),
        act('finish', {'summary': 'Titre rouge'}),
        // Nouvelle instruction : l'agent essaie de s'arrêter tout de suite…
        act('finish', {'summary': 'Déjà fait'}),
        // … il est relancé, et fait vraiment la demande.
        act('write_file', {'path': 'b.css'}, 'p{margin:0}'),
        act('finish', {'summary': 'Marges retirées'}),
      ]);
      await run.run();
      await run.run(followUp: 'Retire les marges des paragraphes');
      expect(run.changes['b.css'], contains('margin:0'));
      expect(run.summary, 'Marges retirées');
      expect(requests[3], contains('sans avoir rien fait'));
    },
  );

  test('une question sans changement se termine après une relance', () async {
    final run = build([
      act('finish', {'summary': 'Rien à faire'}),
      act('finish', {'summary': 'Le titre est déjà rouge'}),
    ]);
    await run.run();
    expect(run.summary, 'Le titre est déjà rouge');
    expect(requests, hasLength(2));
  });
}
