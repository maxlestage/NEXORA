import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/model_catalog.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:nexora/ui/widgets/model_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('les anciens niveaux deviennent les efforts de Claude', () {
    expect(ThinkLevel.parse('equilibre'), ThinkLevel.moyen);
    expect(ThinkLevel.parse('approfondi'), ThinkLevel.eleve);
    expect(ThinkLevel.values.map((l) => l.anthropic), [
      'low',
      'medium',
      'high',
      'xhigh',
      'max',
    ]);
    expect(ThinkLevel.moyen.badge, 'Recommandé');
    expect(ThinkLevel.max.warning, isTrue);
  });

  testWidgets('panneau : modèles principaux, effort, plus de modèles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = (await tester.runAsync(Storage.open))!;
    final s = SettingsState(storage, LlmClient());
    s.catalog = ModelCatalog.parse(
      jsonEncode({
        'updated': '2026-11-09',
        'providers': {
          'anthropic': [
            for (final (id, name) in [
              ('claude-haiku-5-5', 'Claude Haiku 5.5'),
              ('claude-sonnet-5-5', 'Claude Sonnet 5.5'),
              ('claude-opus-5-5', 'Claude Opus 5.5'),
              ('claude-fable-5-1', 'Claude Fable 5.1'),
              ('claude-opus-5', 'Claude Opus 5'),
            ])
              {'id': id, 'name': name, 'release': '2026-10-01'},
          ],
        },
      }),
    );
    ModelRef? picked;
    ThinkLevel? level;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModelSheet(
                  context,
                  current: const ModelRef('anthropic', 'claude-opus-5-5'),
                  level: ThinkLevel.eleve,
                  onModel: (r) => picked = r,
                  onLevel: (l) => level = l,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Sélectionner un modèle'), findsOneWidget);
    // Un par famille, dans l'ordre de Claude, sans « Claude » devant.
    final names = ['Opus 5.5', 'Fable 5.1', 'Sonnet 5.5', 'Haiku 5.5'];
    for (final n in names) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('Opus 5'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Opus 5.5')).dy,
      lessThan(tester.getTopLeft(find.text('Haiku 5.5')).dy),
    );
    expect(find.text('Élevé'), findsOneWidget);

    await tester.tap(find.text('Effort'));
    await tester.pumpAndSettle();
    expect(find.text('Recommandé'), findsOneWidget);
    expect(find.text('Utilisation 3,5× ou plus'), findsOneWidget);
    await tester.tap(find.text('Max'));
    await tester.pumpAndSettle();
    expect(level, ThinkLevel.max);
    expect(find.text('Sélectionner un modèle'), findsOneWidget);

    await tester.tap(find.text('Sonnet 5.5'));
    await tester.pumpAndSettle();
    expect(picked, const ModelRef('anthropic', 'claude-sonnet-5-5'));
    expect(find.text('Sélectionner un modèle'), findsNothing);
  });
}
