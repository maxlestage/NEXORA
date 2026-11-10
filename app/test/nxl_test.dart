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
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```\n$content\n```'}';

const spec1 =
    'OBJECTIF : aucune page du site ne défile horizontalement sur mobile\n'
    'DEMANDES :\n1. Trouver les éléments plus larges que l\'écran et les corriger\n'
    'CONTRAINTES :\n- ne rien cacher du contenu\n'
    'CRITÈRES DE RÉUSSITE :\n- la largeur du document ne dépasse jamais celle '
    'de l\'écran\n- un test le vérifie\n'
    'INTERPRÉTATIONS :\n- « le site » = toutes les pages';

const spec2 =
    'OBJECTIF : le titre est en bleu\nDEMANDES :\n1. Passer h1 en bleu\n'
    'CONTRAINTES :\n- aucune\nCRITÈRES DE RÉUSSITE :\n- h1 est bleu\n'
    'INTERPRÉTATIONS :\n- aucune';

void main() {
  setUp(() {
    AgentRun.compile = true;
    AgentRun.checks = false;
  });
  tearDown(() {
    AgentRun.compile = false;
    AgentRun.checks = true;
  });

  test('chaque demande est traduite en langage NEXORA, affichée et donnée à '
      'l\'agent à chaque étape', () async {
    final requests = <String>[];
    final replies = [
      spec1,
      act('write_file', {'path': 'a.css'}, 'html { overflow-x: clip; }'),
      act('finish', {'summary': 'Fait ✅'}),
      spec2,
      act('write_file', {'path': 'b.css'}, 'h1 { color: blue; }'),
      act('finish', {'summary': 'Bleu ✅'}),
    ];
    var i = 0;
    final run = AgentRun(
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
      task: 'je veux aucun défilement horizontal',
    );
    await run.run();
    // La traduction est demandée avec le format et la demande exacte.
    expect(requests.first, contains('LANGAGE NEXORA'));
    expect(requests.first, contains('je veux aucun défilement horizontal'));
    // Elle est affichée tout de suite : « ce que l'agent a compris ».
    expect(run.steps.first.kind, StepKind.goal);
    expect(run.steps.first.text, startsWith('OBJECTIF : aucune page'));
    // L'agent la reçoit dans ses instructions, avec les mots de l'utilisateur.
    expect(requests[1], contains('En langage NEXORA'));
    expect(requests[1], contains('ne rien cacher du contenu'));
    // Les critères de réussite sont rappelés après chaque résultat.
    expect(requests[2], contains('Critères de réussite à remplir'));
    expect(requests[2], contains('un test le vérifie'));
    expect(run.specs, [spec1]);

    // Une nouvelle instruction est traduite elle aussi, avec le contexte.
    await run.run(followUp: 'mets aussi le titre en bleu');
    expect(requests[3], contains('Demandes précédentes'));
    expect(run.specs, [spec1, spec2]);
    expect(run.summary, 'Bleu ✅');
    expect(run.steps.where((s) => s.kind == StepKind.goal), hasLength(2));
    // Gardé avec la session.
    expect(run.toJson()['specs'], [spec1, spec2]);
  });

  test('traduction ratée : l\'agent travaille avec la demande brute', () async {
    final replies = [
      'Désolé, je ne sais pas.', // pas au format
      act('finish', {'summary': 'ok'}),
      act('finish', {'summary': 'ok'}),
    ];
    var i = 0;
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          await body.drain<void>();
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
      task: 'dis bonjour',
    );
    await run.run();
    expect(run.specs, ['']);
    expect(run.steps.where((s) => s.kind == StepKind.goal), isEmpty);
    expect(run.summary, 'ok');
  });
}
