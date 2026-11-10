import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/main.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('premier lancement : accueil puis onglets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = (await tester.runAsync(Storage.open))!;
    await tester.pumpWidget(
      NexoraApp(
        storage: storage,
        conversationStore: PrefsConversationStore(storage),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Passer'), findsOneWidget);

    await tester.tap(find.text('Passer'));
    await tester.pump(const Duration(milliseconds: 600));
    // L'accueil (le bouton « Nouveau chat » est dans le contenu, plus bas, tant
    // qu'il n'y a aucune conversation).
    expect(find.text('Que voulez-vous créer aujourd\'hui ?'), findsOneWidget);
    expect(find.text('Premiers pas'), findsOneWidget);

    for (final tab in ['Agents', 'Code', 'Modèles', 'Réglages']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Personnaliser'), findsOneWidget);

    await tester.tap(find.text('Modèles').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pollinations'), findsWidgets);

    // Arrête les animations infinies avant la fin du test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('les conversations persistent', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'getting_started_hidden': true,
      'conversations': '[{"id":"a","title":"Projet Flutter","messages":[{"role":"user","content":"Salut"}]}]',
    });
    final storage = (await tester.runAsync(Storage.open))!;
    // Un écran d'iPhone (l'en-tête de l'accueil est haut).
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      NexoraApp(
        storage: storage,
        conversationStore: PrefsConversationStore(storage),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Projet Flutter'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
