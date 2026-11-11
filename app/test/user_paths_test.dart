import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const tree = [
  'README.md',
  'app/lib/main.dart',
  'app/test/app_test.dart',
  'site/src/main.rs',
];

void main() {
  test('un dossier écrit par l\'utilisateur et perdu par la traduction revient '
      'dans les contraintes (essai réel)', () {
    const spec =
        'OBJECTIF : Ajouter slugify dans le fichier utilitaire.\n'
        'DEMANDES :\n1. Ajouter slugify dans le fichier utilitaire.\n'
        '2. Créer app/test/slugify_test.dart.\n'
        'CONTRAINTES :\n- aucune\n'
        'CRITÈRES DE RÉUSSITE :\n- Les tests passent.';
    final out = AgentRun.keepUserPaths(
      spec,
      'Ajoute dans app/lib/utils/ une fonction slugify, avec ses tests dans '
      'app/test/.',
      tree,
    );
    expect(
      out,
      contains(
        'CONTRAINTES :\n- Emplacement écrit par l\'utilisateur, à respecter '
        'tel quel : app/lib/utils/ (dossier à créer',
      ),
    );
    // Déjà présent dans la traduction : pas répété.
    expect(out, isNot(contains('tel quel : app/test/')));
    expect(out, isNot(contains('- aucune')));
    expect(out, contains('CRITÈRES DE RÉUSSITE :\n- Les tests passent.'));
  });

  test('« CONTRAINTES : aucune » sur une ligne devient la liste des '
      'emplacements', () {
    const spec =
        'OBJECTIF : Une route.\nDEMANDES :\n1. Ajouter la route.\n'
        'CONTRAINTES : aucune\nCRITÈRES DE RÉUSSITE :\n- ok';
    final out = AgentRun.keepUserPaths(
      spec,
      'Ajoute une route dans site/src/routes.rs.',
      tree,
    );
    expect(
      out,
      contains(
        'CONTRAINTES :\n- Emplacement écrit par l\'utilisateur, à respecter '
        'tel quel : site/src/routes.rs\nCRITÈRES',
      ),
    );
    expect(out, isNot(contains('routes.rs (dossier')));
  });

  test('sans section CONTRAINTES, elle est ajoutée', () {
    final out = AgentRun.keepUserPaths(
      'OBJECTIF : x\nDEMANDES :\n1. y',
      'Range ça dans app/lib/outils',
      tree,
    );
    expect(
      out,
      endsWith(
        'tel quel : app/lib/outils (dossier à créer s\'il '
        'n\'existe pas : le nouveau code va dedans)',
      ),
    );
    expect(out, contains('\nCONTRAINTES :\n'));
  });

  test('ni « et/ou », ni « Ko/Mo », ni une adresse web, ni un chemin déjà '
      'cité ne changent la traduction', () {
    const spec =
        'OBJECTIF : x\nDEMANDES :\n1. Modifier App/Lib/Main.dart\n'
        'CONTRAINTES :\n- aucune';
    expect(
      AgentRun.keepUserPaths(
        spec,
        'Affiche la taille en Ko/Mo et/ou en octets, comme sur '
        'https://exemple.fr/doc/page.html, dans app/lib/main.dart.',
        tree,
      ),
      spec,
    );
    expect(AgentRun.keepUserPaths('', 'dans app/lib/utils/', tree), '');
  });
}
