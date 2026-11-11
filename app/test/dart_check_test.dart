import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/dart_check.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

// Le fichier réellement écrit par Pollinations pour « ajoute une fonction
// formatDuree, avec ses tests » : « \'0\' » dans un « ${…} » ne compile pas.
const _written = r'''
String formatDuree(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes % 60;
  if (hours > 0) {
    return '${hours} h ${minutes.toString().padLeft(2, \'0\')}';
  }
  return '${d.inSeconds} s';
}
''';

const _fixed = r'''
String formatDuree(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes % 60;
  if (hours > 0) {
    return '$hours h ${minutes.toString().padLeft(2, '0')}';
  }
  return '${d.inSeconds} s';
}
''';

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'app/pubspec.yaml', 'type': 'blob'},
          ],
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
  repo: 'NEXORA',
  branch: 'master',
  task: 'Ajoute une fonction formatDuree, avec ses tests',
)..specs.add('déjà compris');

void main() {
  AgentRun.checks = false;

  test('« \\\'0\\\' » dans une interpolation : repéré, avec la ligne', () {
    final e = dartSyntaxError(_written);
    expect(e, startsWith('ligne 5 '));
    expect(e, contains('barre oblique inverse'));
    expect(e, contains('padLeft(2, \'0\')'));
    expect(dartSyntaxError(_fixed), isNull);
  });

  test('le Dart valide n\'est jamais signalé', () {
    for (final ok in [
      r"final a = 'l\'eau'; final b = "
          '"a \\" b";',
      r"final r = r'C:\dossier\'; final s = r"
          '"\\d+";',
      "final t = '''\nune 'chaîne' \"longue\"\n''';\n",
      'final u = """\n\\""" ok\n""";\n',
      r"final v = 'a ${m['k']} ${f('}')} $x';",
      r'''final w = 'a ${'b ${c("d")}'}';''',
      '// un commentaire avec \' et \\ et {\nvoid f() {}\n',
      '/* imbriqué /* encore \\ */ fin { */\nvoid g() {}\n',
      "/// doc avec ' et (\nvoid h() => [1, 2].map((e) => {e: e});\n",
      r"final x = '\${pas une interpolation';",
      'final y = "multi" \'ple\' r"\\";',
    ]) {
      expect(dartSyntaxError(ok), isNull, reason: ok);
    }
  });

  test('les erreurs certaines sont repérées', () {
    expect(
      dartSyntaxError('void f() {\n  print(1);\n'),
      contains('jamais fermé'),
    );
    expect(
      dartSyntaxError("final a = 'oups;\nvoid f() {}\n"),
      contains('chaîne jamais fermée'),
    );
    expect(
      dartSyntaxError('void f() {\n  g(1];\n}\n'),
      contains('« ] » ferme « ( » ouvert ligne 2'),
    );
    expect(dartSyntaxError('void f() {}\n}\n'), startsWith('ligne 2 '));
    expect(
      dartSyntaxError("final t = '''\nsans fin\n"),
      contains("il manque '''"),
    );
  });

  test('seuls les fichiers Dart sont relus', () {
    expect(AgentRun.dartSyntaxHint('a.rs', _written), isNull);
    expect(AgentRun.dartSyntaxHint('lib/a.dart', _fixed), isNull);
    expect(
      AgentRun.dartSyntaxHint('lib/a.dart', _written),
      contains('lib/a.dart ne compilera pas, ligne 5'),
    );
  });

  test('write_file : le modèle est prévenu tout de suite', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"app/lib/utils.dart",'
          '"content":${jsonEncode(_written)}}}\n```',
    ]);
    await runWith(llm).run();
    expect(seen[1], contains('enregistré en brouillon'));
    expect(seen[1], contains('app/lib/utils.dart ne compilera pas'));
  });

  test('finish est refusé tant que le code ne compile pas', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"app/lib/utils.dart",'
          '"content":${jsonEncode(_written)}}}\n```',
      '```json\n{"tool":"finish","args":{"summary":"fait"}}\n```',
      '```json\n{"tool":"write_file","args":{"path":"app/lib/utils.dart",'
          '"content":${jsonEncode(_fixed)}}}\n```',
      '```json\n{"tool":"finish","args":{"summary":"corrigé"}}\n```',
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen[2], contains('Tu ne peux pas terminer'));
    expect(seen[2], contains('ligne 5'));
    expect(run.summary, 'corrigé');
    expect(run.changes['app/lib/utils.dart'], _fixed);
  });

  test('refusé deux fois au plus : la session se termine quand même', () async {
    final finish = '```json\n{"tool":"finish","args":{"summary":"fait"}}\n```';
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"app/lib/utils.dart",'
          '"content":${jsonEncode(_written)}}}\n```',
      finish,
      finish,
      finish,
    ]);
    final run = runWith(llm);
    await run.run();
    expect(seen.where((s) => s.contains('Tu ne peux pas terminer')).length, 2);
    expect(run.summary, 'fait');
    expect(run.finished, isTrue);
  });
}
