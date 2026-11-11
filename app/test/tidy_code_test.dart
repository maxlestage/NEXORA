import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  group('lignes vides en trop dans le code de l\'agent', () {
    test('Rust : deux lignes vides ramenées à une, fin de fichier propre', () {
      const before = 'pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n';
      const agent =
          'pub const A: u8 = 1;\n\n\n/// Compte.\npub fn n() -> usize {\n'
          '    0\n}\n\n\n#[cfg(test)]\nmod t {}\n\n';
      expect(
        tidyCode('site/src/contenu.rs', agent, before: before),
        'pub const A: u8 = 1;\n\n/// Compte.\npub fn n() -> usize {\n'
        '    0\n}\n\n#[cfg(test)]\nmod t {}\n',
      );
    });

    test('Dart : entre deux fonctions et dans un test', () {
      const agent =
          "import 'a.dart';\n\n\n\nString f() => '';\n  \n\nvoid main() {\n"
          "  test('x', () {});\n}\n\n\n";
      expect(
        tidyCode('app/lib/utils/texte.dart', agent),
        "import 'a.dart';\n\nString f() => '';\n\nvoid main() {\n"
        "  test('x', () {});\n}\n",
      );
    });

    test('un long texte entre guillemets n\'est pas touché', () {
      const html =
          'const PAGE: &str = r#"<p>Un</p>\n\n\n<p>Deux</p>\n"#;\n'
          'const T: &str = "fin.\n\n\nsuite";\n';
      expect(tidyCode('site/src/pages.rs', html), html);
    });

    test('un fichier d\'origine déjà aéré est laissé tel quel', () {
      const before = 'fn a() {}\n\n\nfn b() {}\n\n';
      const agent = 'fn a() {}\n\n\nfn b() {}\n\n\nfn c() {}\n\n';
      expect(tidyCode('src/lib.rs', agent, before: before), agent);
    });

    test('les autres fichiers ne changent pas', () {
      const md = '# Titre\n\n\n- point\n\n';
      expect(tidyCode('README.md', md), md);
      expect(tidyCode('ci.yml', 'a: 1\n\n\nb: 2\n'), 'a: 1\n\n\nb: 2\n');
    });

    test('appliqué aux brouillons de l\'agent (edit_file)', () {
      const src = 'pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n';
      final (out, _) = applyEdit(
        src,
        'pub const A: u8 = 1;\n',
        'pub const A: u8 = 1;\n\n\npub fn n() {}\n',
      );
      expect(
        tidyCode('src/lib.rs', out!, before: src),
        'pub const A: u8 = 1;\n\npub fn n() {}\n\n#[cfg(test)]\nmod t {}\n',
      );
    });
  });

  group('remarques de flutter analyze dans le Dart de l\'agent', () {
    test('essai réel : accolades inutiles et doc en tête de fichier', () {
      const agent =
          '/// Utility functions for duration formatting.\n\n'
          '/// Formats a [Duration].\n'
          'String formatDuree(Duration d) {\n'
          '  final hours = d.inHours;\n'
          "  final minutesStr = '\${d.inMinutes % 60}'.padLeft(2, '0');\n"
          "  return '\${hours} h \${minutesStr} min';\n"
          '}\n';
      expect(
        tidyCode('app/lib/utils/duration_utils.dart', agent),
        '// Utility functions for duration formatting.\n\n'
        '/// Formats a [Duration].\n'
        'String formatDuree(Duration d) {\n'
        '  final hours = d.inHours;\n'
        "  final minutesStr = '\${d.inMinutes % 60}'.padLeft(2, '0');\n"
        "  return '\$hours h \$minutesStr min';\n"
        '}\n',
      );
    });

    test('les accolades utiles restent', () {
      const agent =
          "final a = '\${n}s \${n}_x \${o.p} \${f()} \${n}\$m';\n"
          "final b = '\\\${n} ';\n";
      expect(tidyCode('lib/a.dart', agent), agent);
    });

    test('jamais dans une chaîne brute ni hors d\'un texte', () {
      const agent =
          "final a = r'\${n} ';\n"
          'final b = r"""\n\${n} \n""";\n'
          '// voir \${n} ici\n'
          "final c = '''\n\${n} ok''';\n";
      expect(
        tidyCode('lib/a.dart', agent),
        "final a = r'\${n} ';\n"
        'final b = r"""\n\${n} \n""";\n'
        '// voir \${n} ici\n'
        "final c = '''\n\$n ok''';\n",
      );
    });

    test('interpolations imbriquées', () {
      const agent = "final s = '\${ok ? '\${a} !' : \"\${b}.\"} \${c}';\n";
      expect(
        tidyCode('lib/a.dart', agent),
        "final s = '\${ok ? '\$a !' : \"\$b.\"} \$c';\n",
      );
    });

    test('les lignes du fichier d\'origine restent telles quelles', () {
      const before = "/// Outils.\n\nfinal a = '\${x} ';\n";
      const agent = "/// Outils.\n\nfinal a = '\${x} ';\nfinal b = '\${y} ';\n";
      expect(
        tidyCode('lib/a.dart', agent, before: before),
        "/// Outils.\n\nfinal a = '\${x} ';\nfinal b = '\$y ';\n",
      );
    });

    test('une doc rattachée à quelque chose reste une doc', () {
      const lib = "/// La bibliothèque.\nlibrary;\n\nimport 'a.dart';\n";
      const fn = '/// Compte.\nint n() => 0;\n';
      expect(tidyCode('lib/a.dart', lib), lib);
      expect(tidyCode('lib/b.dart', fn), fn);
      expect(
        tidyCode('lib/c.dart', "/// Outils.\nimport 'a.dart';\n"),
        "// Outils.\nimport 'a.dart';\n",
      );
    });

    test('le Rust n\'est pas concerné', () {
      const rust = '/// Doc.\n\nfn f() { format!("\${x}"); }\n';
      expect(tidyCode('src/lib.rs', rust), rust);
    });
  });
}
