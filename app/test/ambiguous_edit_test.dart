import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const file = '''pub const A: &[&str] = &[
    "a",
];

pub const B: &[&str] = &[
    "b",
];

#[cfg(test)]
mod tests {
    #[test]
    fn t() {}
}
''';

void main() {
  group('passage qui revient plusieurs fois', () {
    test('le refus montre chaque copie avec sa ligne et ses voisines', () {
      final (out, why) = applyEdit(file, '];', '];\n\npub fn f() {}');
      expect(out, isNull);
      expect(why, contains('apparaît 2 fois (lignes 3, 7)'));
      expect(why, contains('"line"'));
      expect(why, contains('Copie de la ligne 3 :'));
      expect(why, contains(' 2:     "a",'));
      expect(why, contains('>3: ];'));
      expect(why, contains('Copie de la ligne 7 :'));
      expect(why, contains(' 6:     "b",'));
    });

    test('"line" choisit la copie la plus proche, les autres restent', () {
      final (out, note) = applyEdit(file, '];', '];\n\npub fn f() {}', near: 8);
      expect(note, '1 remplacement (ligne 7)');
      expect(out, contains('    "b",\n];\n\npub fn f() {}\n\n#[cfg(test)]'));
      expect(out, contains('    "a",\n];\n\npub const B'));
    });

    test('la première copie peut aussi être choisie', () {
      final (out, _) = applyEdit(file, '];', '];\n// fin de A', near: 3);
      expect(out, contains('    "a",\n];\n// fin de A\n\npub const B'));
      expect('// fin de A'.allMatches(out!).length, 1);
    });

    test('une ligne à égale distance de deux copies : refus expliqué', () {
      final (out, why) = applyEdit(file, '];', '];\nx', near: 5);
      expect(out, isNull);
      expect(why, contains('égale distance'));
    });

    test('un ajout avant une déclaration choisie garde son commentaire', () {
      const src = '/// Doc de f.\nfn f() {}\n\n/// Doc de g.\nfn f() {}\n';
      final (out, note) = applyEdit(
        src,
        'fn f() {}',
        'fn neuf() {}\n\nfn f() {}',
        near: 5,
      );
      expect(note, contains('(ligne 5)'));
      expect(
        out,
        '/// Doc de f.\nfn f() {}\n\nfn neuf() {}\n\n/// Doc de g.\nfn f() {}\n',
      );
    });

    test('rien ne change sans ambiguïté ni avec "all"', () {
      expect(applyEdit(file, '"a",', '"z",').$2, '1 remplacement');
      expect(applyEdit(file, '"a",', '"z",', near: 40).$2, '1 remplacement');
      final (out, note) = applyEdit(file, '];', '] ;', all: true);
      expect(note, '2 remplacements');
      expect(out, isNot(contains('];')));
    });

    test('un passage trop courant renvoie vers des lignes plus parlantes', () {
      final many = List.generate(10, (i) => 'x$i();\n}\n').join();
      final (_, why) = applyEdit(many, '}', '}\n');
      expect(why, contains('apparaît 10 fois'));
      expect(why, contains('… et 4 autres'));
    });
  });
}
