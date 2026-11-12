import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  group('résumé de fin sans résultat invérifiable', () {
    test('le cas de l\'essai réel : la ligne de constat disparaît', () {
      const summary =
          '✔ Modifications apportées:\n'
          '1. `app/lib/models/usage.dart` – la méthode `label` ajoute « repart '
          'dans Xs ».\n'
          '2. `app/test/usage_reset_test.dart` – nouveaux tests.\n'
          '\n'
          'Tous les tests passent et la CI reste verte.';
      final out = stripUnverifiedClaims(summary);
      expect(out, isNot(contains('passent')));
      expect(out, isNot(contains('CI')));
      expect(out, contains('1. `app/lib/models/usage.dart`'));
      expect(out, contains('2. `app/test/usage_reset_test.dart` – nouveaux'));
      expect(out.endsWith('nouveaux tests.'), isTrue);
    });

    test('seule la proposition qui affirme le résultat est retirée', () {
      expect(
        stripUnverifiedClaims('Label modifié ; tous les tests passent.'),
        'Label modifié.',
      );
      expect(
        stripUnverifiedClaims(
          'Ajouté formatReset, ses tests et la doc, et le code compile.',
        ),
        'Ajouté formatReset, ses tests et la doc.',
      );
      expect(
        stripUnverifiedClaims('Les tests passent. Le titre est en bleu.'),
        'Le titre est en bleu.',
      );
      expect(
        stripUnverifiedClaims('Done: added slugify. All tests pass.'),
        'Done: added slugify.',
      );
    });

    test('une puce qui ne contenait que le constat disparaît', () {
      expect(
        stripUnverifiedClaims('- Bouton ajouté\n- CI verte\n3. Tests OK'),
        '- Bouton ajouté\n3. Tests OK',
      );
      expect(
        stripUnverifiedClaims('1. Bouton ajouté.\n2. Les tests passent.'),
        '1. Bouton ajouté.',
      );
    });

    test('un but n\'est pas un constat : il reste', () {
      for (final s in [
        'Test corrigé pour que la CI reste verte.',
        'Ajouté un test qui vérifie que les tests passent sans réseau.',
        'Mis à jour usage_test.dart afin que les tests passent avec le reset.',
        'Updated the fixture so that all tests pass.',
      ]) {
        expect(stripUnverifiedClaims(s), s, reason: s);
      }
    });

    test('un résumé sans affirmation est rendu tel quel', () {
      for (final s in [
        'Titre passé en bleu.',
        'Ajouté 3 tests unitaires pour compareVersions.\n- cas vide\n- cas égal',
        'Le workflow CI lance maintenant cargo clippy.',
        'Les tests de la page d\'accueil vérifient le titre.',
        '',
      ]) {
        expect(stripUnverifiedClaims(s), s, reason: s);
      }
    });

    test('un résumé fait uniquement du constat devient vide', () {
      expect(stripUnverifiedClaims('Tous les tests passent.'), '');
    });
  });
}
