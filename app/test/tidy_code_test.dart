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
}
