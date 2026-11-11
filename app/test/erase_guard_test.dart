import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Le début réel de app/lib/services/diff.dart (4 174 caractères en vrai).
const _diff = '''/// Une comparaison ligne à ligne.
library;

enum DiffKind { same, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

  final DiffKind kind;
  final String text;
  final int? oldNo;
  final int? newNo;
}

class DiffResult {
  const DiffResult(this.lines, {this.truncated = false});

  final List<DiffLine> lines;
  final bool truncated;
}
''';

/// Ce qu'a écrit Pollinations en essai réel : seulement la fonction ajoutée.
const _onlyNew =
    '''// Added function to compute added and removed lines from a unified diff
List<int> diffStats(String diff) {
  int added = 0;
  int removed = 0;
  for (final line in diff.split('\\n')) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+')) added++;
    if (line.startsWith('-')) removed++;
  }
  return [added, removed];
}
''';

GitHubApi _fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'lib/diff.dart', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (req.url.path.endsWith('/contents/lib/diff.dart')) {
      return http.Response(
        jsonEncode({
          'sha': 's',
          'content': base64.encode(utf8.encode(_diff)),
          'encoding': 'base64',
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

(AgentRun, List<String>) _run(List<String> replies) {
  var i = 0;
  final seen = <String>[];
  final llm = LlmClient(
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
  );
  final run = AgentRun(
    llm: llm,
    github: _fake(),
    provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
    apiKey: null,
    model: 'openai',
    owner: 'max',
    repo: 'app',
    branch: 'main',
    task: 'Ajoute une fonction diffStats dans lib/diff.dart',
  )..specs.add('déjà compris');
  return (run, seen);
}

String _write(String content, {Map<String, Object> extra = const {}}) =>
    '```json\n${jsonEncode({
      'tool': 'write_file',
      'args': {'path': 'lib/diff.dart', 'content': content, ...extra},
    })}\n```';

void main() {
  AgentRun.checks = false;

  group('erasedLines', () {
    test('seulement la fonction ajoutée : presque tout est effacé', () {
      final gone = erasedLines(_diff, _diff, _onlyNew)!;
      expect(gone, contains('class DiffResult {'));
      expect(gone, contains('enum DiffKind { same, added, removed }'));
    });

    test('le fichier complet avec l\'ajout : rien à signaler', () {
      expect(erasedLines(_diff, _diff, '$_diff\n$_onlyNew'), isNull);
    });

    test('quelques lignes retirées ou réécrites : rien à signaler', () {
      final edited = _diff
          .replaceFirst('  final bool truncated;\n', '')
          .replaceFirst('final int? oldNo;', 'final int? oldLine;');
      expect(erasedLines(_diff, _diff, edited), isNull);
    });

    test('un tout petit fichier n\'est pas surveillé', () {
      expect(erasedLines('a = 1\nb = 2\n', 'a = 1\nb = 2\n', 'c = 3'), isNull);
    });

    test('les lignes déjà retirées par l\'agent ne comptent pas', () {
      // L'agent a déjà enlevé DiffLine et DiffResult (edit_file) : réécrire
      // le reste sans eux est voulu.
      final now = _diff.substring(0, _diff.indexOf('class DiffLine'));
      expect(erasedLines(_diff, now, '$now\n$_onlyNew'), isNull);
    });
  });

  test('write_file avec seulement la fonction ajoutée : refusé, le fichier '
      'reste intact, l\'agent apprend comment ajouter', () async {
    final (run, seen) = _run([_write(_onlyNew)]);
    await run.run();
    expect(run.changes.containsKey('lib/diff.dart'), isFalse);
    expect(seen[1], contains('rien n\'est écrit'));
    expect(seen[1], contains('REMPLACE tout lib/diff.dart'));
    expect(seen[1], contains('13 des 13 lignes de code existantes'));
    expect(seen[1], contains('« const DiffLine('));
    expect(seen[1], isNot(contains('« /// Une comparaison')));
    expect(seen[1], contains('"at_end": true'));
  });

  test(
    'refusé, puis l\'ajout à la fin : le fichier garde tout son code',
    () async {
      final (run, _) = _run([
        _write(_onlyNew),
        _write(_onlyNew, extra: {'at_end': true}),
      ]);
      await run.run();
      final draft = run.changes['lib/diff.dart']!;
      expect(draft, startsWith(_diff));
      expect(draft, contains('List<int> diffStats(String diff) {'));
    },
  );

  test('le contenu complet avec l\'ajout est écrit du premier coup', () async {
    final (run, seen) = _run([_write('$_diff\n$_onlyNew')]);
    await run.run();
    expect(run.changes['lib/diff.dart'], contains('class DiffResult {'));
    expect(run.changes['lib/diff.dart'], contains('diffStats'));
    expect(seen[1], contains('enregistré en brouillon'));
  });

  test(
    '"force": true efface vraiment le code (demande de suppression)',
    () async {
      final (run, _) = _run([
        _write(_onlyNew, extra: {'force': true}),
      ]);
      await run.run();
      expect(run.changes['lib/diff.dart'], isNot(contains('class DiffResult')));
    },
  );

  test('un nouveau fichier est écrit sans vérification', () async {
    final (run, _) = _run([
      '```json\n${jsonEncode({
        'tool': 'write_file',
        'args': {'path': 'lib/stats.dart', 'content': _onlyNew},
      })}\n```',
    ]);
    await run.run();
    expect(run.changes['lib/stats.dart'], contains('diffStats'));
  });
}
