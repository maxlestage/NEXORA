import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

/// Le début de app/lib/services/diff.dart, tel que l'agent l'a modifié en
/// essai réel (Pollinations).
const _diff = '''class DiffResult {
  int get added => 0;
}

/// Compare deux textes ligne à ligne (plus longue sous-suite commune, après
/// avoir retiré le début et la fin identiques).
DiffResult lineDiff(String? before, String? after) {
  return const DiffResult();
}
''';

const _newFn = '''/// Le nombre de lignes ajoutées et supprimées.
int countChangedLines(String before, String after) {
  final r = lineDiff(before, after);
  return r.added + r.removed;
}

''';

void main() {
  test('une fonction ajoutée avant une autre ne lui vole plus sa doc', () {
    const old = 'DiffResult lineDiff(String? before, String? after) {';
    final (out, note) = applyEdit(_diff, old, '$_newFn$old');
    expect(out, isNotNull);
    expect(note, contains('au-dessus du commentaire'));
    // La doc de lineDiff reste collée à lineDiff…
    expect(
      out,
      contains(
        'identiques).\nDiffResult lineDiff(String? before, String? after) {',
      ),
    );
    // … et la nouvelle fonction arrive au-dessus, avec la sienne.
    expect(
      out!.indexOf('int countChangedLines'),
      lessThan(out.indexOf('/// Compare deux textes')),
    );
    expect(out, contains('$_newFn/// Compare deux textes'));
    // Rien d'autre ne change.
    expect(out.replaceFirst(_newFn, ''), _diff);
  });

  test('annotations et attributs restent avec leur déclaration', () {
    const dart = 'class A {\n  @override\n  String toString() => "a";\n}\n';
    final (d, _) = applyEdit(
      dart,
      '  String toString() => "a";',
      '  int get n => 1;\n\n  String toString() => "a";',
    );
    expect(
      d,
      'class A {\n  int get n => 1;\n\n  @override\n  String toString() => '
      '"a";\n}\n',
    );

    const rust = '/// Santé.\n#[get("/sante")]\nasync fn sante() {}\n';
    final (r, _) = applyEdit(
      rust,
      'async fn sante() {}',
      'async fn version() {}\n\nasync fn sante() {}',
    );
    expect(
      r,
      'async fn version() {}\n\n/// Santé.\n#[get("/sante")]\nasync fn '
      'sante() {}\n',
    );

    const js = '/**\n * Somme.\n */\nfunction add(a, b) {}\n';
    final (j, _) = applyEdit(
      js,
      'function add(a, b) {}',
      'function sub(a, b) {}\n\nfunction add(a, b) {}',
    );
    expect(
      j,
      'function sub(a, b) {}\n\n/**\n * Somme.\n */\nfunction add(a, b) {}\n',
    );
  });

  test(
    'rien ne bouge sans commentaire au-dessus, ni pour un autre remplacement',
    () {
      const plain = 'int a() => 1;\n\nint b() => 2;\n';
      final (p, note) = applyEdit(
        plain,
        'int b() => 2;',
        'int c() => 3;\nint b() => 2;',
      );
      expect(p, 'int a() => 1;\n\nint c() => 3;\nint b() => 2;\n');
      expect(note, '1 remplacement');

      // Une vraie modification (pas un simple ajout avant) : telle quelle.
      final (m, _) = applyEdit(
        _diff,
        'DiffResult lineDiff(String? before, String? after) {',
        'DiffResult lineDiff(String before, String after) {',
      );
      expect(m, contains('identiques).\nDiffResult lineDiff(String before,'));

      // Un ajout sur la même ligne : tel quel.
      const line = '/// Doc.\nfinal x = 1;\n';
      final (l, _) = applyEdit(
        line,
        'final x = 1;',
        'const y = 2; final x = 1;',
      );
      expect(l, '/// Doc.\nconst y = 2; final x = 1;\n');

      // old commence par le commentaire lui-même : l'ajout va déjà au-dessus.
      final (c, _) = applyEdit(
        _diff,
        '/// Compare deux textes',
        'int z() => 0;\n\n/// Compare deux textes',
      );
      expect(c, contains('int z() => 0;\n\n/// Compare deux textes'));

      // Un titre Markdown n'est pas un commentaire : l'ajout reste dessous.
      const md = '# Titre\nPremier paragraphe.\n';
      final (t, _) = applyEdit(
        md,
        'Premier paragraphe.',
        'Introduction.\n\nPremier paragraphe.',
      );
      expect(t, '# Titre\nIntroduction.\n\nPremier paragraphe.\n');
    },
  );
}
