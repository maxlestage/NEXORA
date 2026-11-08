import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/diff.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/ui/settings/credits_screen.dart';

void main() {
  group('comparaison ligne à ligne', () {
    test('ajouts, suppressions et lignes identiques', () {
      final d = lineDiff('a\nb\nc\nd\n', 'a\nB\nc\nd\ne\n');
      expect(d.added, 2); // B, e
      expect(d.removed, 1); // b
      expect(d.lines.map((l) => '${l.kind.name[0]}${l.text}').toList(), [
        'sa',
        'rb',
        'aB',
        'sc',
        'sd',
        'ae',
      ]);
    });

    test('fichier nouveau et fichier supprimé', () {
      expect(lineDiff(null, 'x\ny').added, 2);
      expect(lineDiff('x\ny\n', null).removed, 2);
    });

    test('contexte replié autour des changements', () {
      final before = List.generate(30, (i) => 'l$i').join('\n');
      final after = before.replaceFirst('l15', 'L15');
      final rows = withContext(lineDiff(before, after).lines, context: 2);
      // … , 2 lignes, -l15, +L15, 2 lignes, …
      expect(rows.first, isNull);
      expect(rows.last, isNull);
      expect(rows.whereType<DiffLine>().length, 6);
    });
  });

  test('brouillons acceptés, refusés et modifiés', () {
    final run = AgentRun(
      llm: LlmClient(),
      github: GitHubApi(null),
      provider: providersCatalog.first,
      apiKey: null,
      model: 'm',
      owner: 'o',
      repo: 'r',
      branch: 'main',
      task: 't',
    );
    run.changes.addAll({'a.dart': 'A\n', 'b.dart': null, 'c.md': 'C\n'});
    expect(run.accepted.length, 3);
    run.setAccepted('b.dart', false);
    expect(run.accepted.keys, ['a.dart', 'c.md']);
    run.setAllAccepted(false);
    expect(run.accepted, isEmpty);
    run.editDraft('c.md', 'C2\n');
    expect(run.accepted, {'c.md': 'C2\n'});
    run.setAllAccepted(true);
    expect(run.accepted.length, 3);
  });

  test('crédits', () {
    expect(appAuthor, 'Maxime Nathan Lestage');
  });
}
