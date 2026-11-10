import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const file = '''class A {
  Widget build() {
    return IconButton(
      icon: const Icon(Icons.send),
      onPressed: onSend,
    );
  }
}
''';

void main() {
  group('remplacement dont seule l\'indentation diffère', () {
    test('appliqué, avec l\'indentation du fichier', () {
      final (out, note) = applyEdit(
        file,
        'return IconButton(\n  icon: const Icon(Icons.send),',
        'return IconButton(\n  tooltip: \'Envoyer le message\',\n'
            '  icon: const Icon(Icons.send),',
      );
      expect(note, contains('indentation'));
      expect(
        out,
        contains(
          '    return IconButton(\n'
          '      tooltip: \'Envoyer le message\',\n'
          '      icon: const Icon(Icons.send),\n'
          '      onPressed: onSend,',
        ),
      );
      // Le reste du fichier est intact, fin de ligne comprise.
      expect(out, startsWith('class A {\n  Widget build() {\n'));
      expect(out, endsWith('  }\n}\n'));
    });

    test('jamais appliqué au hasard si les lignes reviennent deux fois', () {
      const twice = '  a();\n  b();\n\n    a();\n    b();\n';
      expect(applyEdit(twice, 'a();\nb();', 'c();').$1, isNull);
    });
  });

  group('passage introuvable : le plus proche est montré', () {
    test('avec ses numéros de ligne', () {
      final (out, why) = applyEdit(
        file,
        "IconButton(\n  tooltip: 'Envoyer',\n  icon: const Icon(Icons.send),",
        'x',
      );
      expect(out, isNull);
      expect(why, contains('passage introuvable'));
      expect(why, contains('Le passage le plus proche'));
      expect(why, contains('4:       icon: const Icon(Icons.send),'));
    });

    test('rien de ressemblant : pas de passage inventé', () {
      expect(nearestPassage(file, 'fn main() { println!("x"); }'), isNull);
      final (_, why) = applyEdit(file, 'zzz qqq', 'x');
      expect(why, isNot(contains('le plus proche')));
    });
  });
}
