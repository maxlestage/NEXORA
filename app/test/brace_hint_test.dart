import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/dart_check.dart';
import 'package:nexora/services/rust_check.dart';

/// Essai réel : un test collé au milieu d'un autre, dont la fin reste dehors.
const rust =
    '#[cfg(test)]\n' // 1
    'mod tests {\n' // 2
    '    #[test]\n' // 3
    '    fn iles() {\n' // 4
    '        let accueil = page();\n' // 5
    '    }\n' // 6
    '\n' // 7
    '    #[test]\n' // 8
    '    fn version() {\n' // 9
    '        assert_eq!(v(), "1");\n' // 10
    '    }\n' // 11
    '        for ile in ["a", "b"] {\n' // 12
    '            assert!(accueil.contains(ile));\n' // 13
    '        }\n' // 14
    '    }\n' // 15
    '}\n'; // 16

const dart =
    'void main() {\n' // 1
    '  test(\'a\', () {\n' // 2
    '    final x = 1;\n' // 3
    '  });\n' // 4
    '}\n' // 5
    '    expect(x, 1);\n' // 6
    '    if (x > 0) {\n' // 7
    '      print(x);\n' // 8
    '    }\n' // 9
    '  });\n' // 10
    '}\n'; // 11

void main() {
  test('Rust : la ligne laissée hors de sa fonction est désignée', () {
    final e = rustSyntaxError(rust)!;
    expect(e, startsWith('ligne 16 '));
    expect(e, contains('le décalage commence sans doute ligne 12 (« for ile'));
    expect(e, contains('la « } » de la ligne 11 juste avant'));
    // L'ancien indice (la dernière fermeture mal alignée) n'est plus donné.
    expect(e, isNot(contains('alignée autrement')));
  });

  test('Dart : la ligne laissée hors de sa fonction est désignée', () {
    final e = dartSyntaxError(dart)!;
    expect(e, contains('ferme quelque chose qui n\'a jamais été ouvert'));
    expect(e, contains('le décalage commence sans doute ligne 6 (« expect'));
    expect(e, contains('la « } » de la ligne 5 juste avant'));
  });

  test('sans code orphelin, l\'erreur reste la même', () {
    // Une accolade en trop seule : pas de ligne plus indentée après une « } ».
    final e = rustSyntaxError('fn f() {\n    g();\n}\n}\n')!;
    expect(e, startsWith('ligne 4 '));
    expect(e, isNot(contains('plus indentée')));
    // L'indice d'alignement reste donné quand il n'y a pas de code orphelin.
    final a = rustSyntaxError(
      'fn f() {\n    g(|| {\n        h();\n      });\n    });\n}\n',
    )!;
    expect(a, contains('le décalage commence sans doute ligne 4'));
    expect(a, contains('alignée autrement'));
    final d = dartSyntaxError('void f() {\n  g();\n}\n}\n')!;
    expect(d, isNot(contains('plus indentée')));
  });

  test('le code valide n\'est jamais signalé', () {
    expect(
      rustSyntaxError(rust.replaceFirst('    }\n        for', '        for')),
      isNull,
    );
    // Suites d'expression et else après une « } » seule : du code normal.
    const ok =
        'fn f() {\n'
        '    let x = if a {\n'
        '        1\n'
        '    }\n'
        '        + 2;\n'
        '    match y {\n'
        '        _ => {}\n'
        '    }\n'
        '}\n';
    expect(rustSyntaxError(ok), isNull);
    // Une accolade dans une chaîne ou une interpolation ne compte pas.
    expect(
      dartSyntaxError("void f() {\n  final s = '\${x\n}';\n}\n}\n"),
      isNot(contains('plus indentée')),
    );
  });
}
