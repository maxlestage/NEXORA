import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Une réponse en flux ; `cut` : la connexion se ferme avant la fin (ni
/// raison d'arrêt, ni `[DONE]`).
http.StreamedResponse sse(String text, {bool cut = false}) =>
    http.StreamedResponse(
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
        if (!cut) utf8.encode('data: [DONE]\n\n'),
      ]),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

String act(String tool, Map args, [String? content]) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```'
    '${content == null ? '' : '\n```\n$content\n```'}';

/// Ce que la traduction a vraiment rendu en essai réel (Pollinations) : la
/// demande s'arrête au premier mot.
const _cutSpec =
    'OBJECTIF : Ajouter une fonction publique countChangedLines dans '
    'app/lib/services/diff.dart et un test unitaire.\n\n'
    'DEMANDES :\n1. Dans';

const _fullSpec =
    'OBJECTIF : Ajouter une fonction publique countChangedLines dans '
    'app/lib/services/diff.dart et un test unitaire.\n'
    'DEMANDES :\n1. Ajouter countChangedLines(String before, String after) '
    'dans app/lib/services/diff.dart\n2. Écrire son test unitaire\n'
    'CONTRAINTES :\n- garder la signature demandée\n'
    'CRITÈRES DE RÉUSSITE :\n- le test passe\n'
    'INTERPRÉTATIONS :\n- aucune';

const _task =
    'Dans l\'app, ajoute dans app/lib/services/diff.dart une fonction '
    'publique countChangedLines(String before, String after), avec un test.';

AgentRun _run(
  List<http.StreamedResponse Function()> replies,
  List<String> seen,
) {
  var i = 0;
  return AgentRun(
    llm: LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        seen.add(await body.bytesToString());
        return i < replies.length
            ? replies[i++]()
            : sse(act('finish', {'summary': 'Fait ✅'}));
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
    repo: 'NEXORA',
    branch: 'master',
    task: _task,
  );
}

void main() {
  setUp(() {
    AgentRun.compile = true;
    AgentRun.checks = false;
  });
  tearDown(() {
    AgentRun.compile = false;
    AgentRun.checks = true;
  });

  test('une traduction arrêtée au premier mot des demandes est incomplète', () {
    expect(AgentRun.specComplete(_cutSpec), isFalse);
    expect(AgentRun.specComplete(_cutSpec, cut: true), isFalse);
    expect(AgentRun.specComplete(_fullSpec), isTrue);
    expect(AgentRun.specComplete(_fullSpec, cut: true), isTrue);
    // Les titres en gras et les demandes en tableau restent compris.
    expect(
      AgentRun.specComplete(
        '**OBJECTIF**\nAjouter la fonction demandée\n\n**DEMANDES**\n'
        '| # | Demande |\n| 1 | Implémenter la fonction |',
      ),
      isTrue,
    );
    // Sans demandes du tout.
    expect(
      AgentRun.specComplete('OBJECTIF : ajouter la fonction demandée'),
      isFalse,
    );
    // Coupée avant les critères : les demandes ont pu être tronquées.
    expect(
      AgentRun.specComplete(
        'OBJECTIF : ajouter la fonction demandée\nDEMANDES :\n'
        '1. Ajouter la fonction\n2. Écrire le te',
        cut: true,
      ),
      isFalse,
    );
    // Complète mais sans critères, non coupée : acceptée.
    expect(
      AgentRun.specComplete(
        'OBJECTIF : ajouter la fonction demandée\nDEMANDES :\n'
        '1. Ajouter la fonction et son test',
      ),
      isTrue,
    );
  });

  test(
    'une traduction coupée en route est redemandée, et la bonne sert',
    () async {
      final seen = <String>[];
      final run = _run([
        () => sse(_cutSpec, cut: true),
        () => sse(_fullSpec),
        () => sse(act('finish', {'summary': 'Fait ✅'})),
      ], seen);
      await run.run();
      // La même demande de traduction, deux fois.
      expect(seen[1], contains('LANGAGE NEXORA'));
      expect(run.specs, hasLength(1));
      expect(run.specs.first, startsWith(_fullSpec));
      final goals = run.steps.where((s) => s.kind == StepKind.goal).toList();
      expect(goals, hasLength(1));
      expect(goals.first.text, contains('2. Écrire son test unitaire'));
      expect(goals.first.text, isNot(contains('1. Dans\n')));
      // L'agent reçoit la traduction entière.
      expect(seen[2], contains('2. Écrire son test unitaire'));
      expect(run.summary, 'Fait ✅');
    },
  );

  test(
    'une traduction tronquée sans signal de coupure est aussi redemandée',
    () async {
      final seen = <String>[];
      final run = _run([
        () => sse(_cutSpec),
        () => sse(_fullSpec),
        () => sse(act('finish', {'summary': 'Fait ✅'})),
      ], seen);
      await run.run();
      expect(run.specs.first, startsWith(_fullSpec));
    },
  );

  test(
    'deux traductions coupées : l\'agent travaille avec la demande brute',
    () async {
      final seen = <String>[];
      final run = _run([
        () => sse(_cutSpec, cut: true),
        () => sse(_cutSpec, cut: true),
        () => sse(act('finish', {'summary': 'Fait ✅'})),
      ], seen);
      await run.run();
      expect(run.specs, ['']);
      expect(run.steps.where((s) => s.kind == StepKind.goal), isEmpty);
      // La demande de l'utilisateur, mot pour mot, sans traduction tronquée.
      expect(
        seen[2],
        contains('countChangedLines(String before, String after)'),
      );
      expect(seen[2], isNot(contains('1. Dans\n')));
      expect(run.summary, 'Fait ✅');
    },
  );

  test('complete() signale une réponse coupée', () async {
    String? stop;
    final out =
        await LlmClient(
          clientFactory: () => MockClient.streaming(
            (req, body) async => sse('Bonjour', cut: true),
          ),
        ).complete(
          provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
          apiKey: 'k',
          model: 'm',
          messages: [LlmMessage('user', 'salut')],
          onStop: (s) => stop = s,
        );
    expect(out, 'Bonjour');
    expect(stop, 'cut');
  });
}
