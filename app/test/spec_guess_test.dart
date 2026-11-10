import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const guessed =
    'OBJECTIF : compter les versions publiées\n'
    'DEMANDES :\n'
    '1. Dans le fichier **site/src/export.rs**, ajouter une fonction qui compte '
    'les titres de version de site/src/nouveautes.md\n'
    '2. Ajouter un test unitaire Rust\n'
    'CONTRAINTES :\n'
    '- Le fichier modifié doit être exactement **site/src/export.rs**.\n'
    'CRITÈRES DE RÉUSSITE :\n'
    '- cargo test passe\n'
    'INTERPRÉTATIONS :\n'
    '- aucune';

const files = [
  'site/src/contenu.rs',
  'site/src/export.rs',
  'site/src/nouveautes.md',
];

void main() {
  test('un fichier deviné ne devient plus une contrainte stricte', () {
    final out = AgentRun.markGuesses(
      guessed,
      'Dans le site (dossier site/), ajoute dans le fichier qui gère les '
      'nouveautés une fonction qui compte les versions publiées, avec un test.',
      files,
    );
    final contraintes = out.substring(
      out.indexOf('CONTRAINTES'),
      out.indexOf('CRITÈRES'),
    );
    expect(contraintes, isNot(contains('export.rs')));
    expect(contraintes, contains('- aucune'));
    final interp = out.substring(out.indexOf('INTERPRÉTATIONS'));
    expect(interp, contains('Supposé (à vérifier dans le dépôt)'));
    expect(interp, contains('site/src/export.rs, site/src/nouveautes.md'));
    expect(interp, contains('modifie le bon fichier'));
    expect(interp, isNot(contains('- aucune')));
    // La demande elle-même est gardée.
    expect(out, contains('1. Dans le fichier **site/src/export.rs**'));
  });

  test('un fichier nommé par l\'utilisateur reste une contrainte', () {
    final out = AgentRun.markGuesses(
      guessed,
      'Ajoute dans export.rs une fonction qui compte les versions de '
      'site/src/nouveautes.md',
      files,
    );
    expect(out, guessed);
  });

  test('sans fichier cité, la traduction est inchangée', () {
    const spec =
        'OBJECTIF : le titre est en bleu\nDEMANDES :\n1. Passer h1 en bleu\n'
        'CONTRAINTES :\n- aucune\nCRITÈRES DE RÉUSSITE :\n- h1 est bleu\n'
        'INTERPRÉTATIONS :\n- aucune';
    expect(AgentRun.markGuesses(spec, 'Mets le titre en bleu', files), spec);
  });

  test('sans section INTERPRÉTATIONS, elle est ajoutée', () {
    const spec =
        'OBJECTIF : corriger le menu\nDEMANDES :\n1. Corriger app/lib/menu.dart\n'
        'CONTRAINTES :\n- ne rien casser';
    final out = AgentRun.markGuesses(spec, 'Corrige le menu');
    expect(out, contains('CONTRAINTES :\n- ne rien casser'));
    expect(out, endsWith('modifie le bon fichier.'));
    expect(out, contains('INTERPRÉTATIONS :\n- Fichiers supposés'));
    expect(out, contains('app/lib/menu.dart'));
  });

  test('un nom de domaine n\'est pas pris pour un fichier', () {
    const spec =
        'OBJECTIF : lien\nDEMANDES :\n1. Ajouter un lien vers pollinations.ai\n'
        'CONTRAINTES :\n- aucune';
    expect(AgentRun.markGuesses(spec, 'Ajoute un lien', files), spec);
  });
}
