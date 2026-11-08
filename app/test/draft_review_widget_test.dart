import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/ui/theme.dart';
import 'package:nexora/ui/workspace/draft_review_screen.dart';

void main() {
  testWidgets('relire, refuser puis valider les brouillons', (tester) async {
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
    run.changes.addAll({
      'lib/a.dart': 'un\ndeux bis\ntrois\n',
      'README.md': '# Nouveau\n',
    });
    run.originals.addAll({
      'lib/a.dart': 'un\ndeux\ntrois\n',
      'README.md': null,
    });
    var validated = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: DraftReviewScreen(run: run, onValidate: () async => validated++),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Valider 2 brouillons'), findsOneWidget);

    // Refuser README.md avec sa case.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Valider 1 brouillon'), findsOneWidget);

    // Ouvrir la comparaison de lib/a.dart.
    await tester.tap(find.text('lib/a.dart'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('deux bis'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Valider 1 brouillon'));
    await tester.pump();
    expect(validated, 1);
  });
}
