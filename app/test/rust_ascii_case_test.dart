import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/rust_check.dart';

// Ce que Pollinations a réellement écrit pour « ajoute slug() : minuscules,
// accents retirés (é→e, à→a, ç→c…) » : « À » n'est jamais reconnu.
const _written = '''
pub fn slug(titre: &str) -> String {
    fn deaccent(c: char) -> Option<char> {
        match c {
            'á' | 'à' | 'â' => Some('a'),
            'é' | 'è' | 'ê' | 'ë' => Some('e'),
            'ç' => Some('c'),
            _ => None,
        }
    }
    let mut result = String::new();
    for ch in titre.chars() {
        let ch = ch.to_ascii_lowercase();
        let ch = deaccent(ch).unwrap_or(ch);
        if ch.is_ascii_alphanumeric() {
            result.push(ch);
        }
    }
    result
}
''';

void main() {
  test('le cas de l\'essai réel est signalé, avec la correction', () {
    final p = rustAsciiCaseProblem(_written);
    expect(p, startsWith('ligne 12 (« let ch = ch.to_ascii_lowercase(); »)'));
    expect(p, contains('« Á » reste « Á »'));
    expect(p, contains('(ligne 4)'));
    expect(p, contains('to_lowercase()'));
    final hint = AgentRun.rustAsciiCaseHint('site/src/contenu.rs', _written);
    expect(hint, contains('erreur de logique dans site/src/contenu.rs'));
  });

  test('version Unicode ou majuscules déjà écrites : rien à dire', () {
    expect(
      rustAsciiCaseProblem(
        _written.replaceFirst(
          'for ch in titre.chars() {\n        let ch = ch.to_ascii_lowercase();',
          'for ch in titre.chars().flat_map(char::to_lowercase) {',
        ),
      ),
      isNull,
    );
    expect(
      rustAsciiCaseProblem(
        _written.replaceAll(
          '.to_ascii_lowercase()',
          '.to_lowercase().next().unwrap()',
        ),
      ),
      isNull,
    );
    const both = '''
fn f(c: char) -> char {
    match c.to_ascii_lowercase() {
        'é' | 'É' => 'e',
        c => c,
    }
}
''';
    expect(rustAsciiCaseProblem(both), isNull);
    // Le slug() du site, corrigé : tout passe d'abord en minuscules Unicode.
    const site = '''
pub fn slug(nom: &str) -> String {
    for c in nom.trim().chars().flat_map(char::to_lowercase) {
        let c = match c {
            'à' | 'â' => 'a',
            c => c.to_ascii_lowercase(),
        };
    }
}
''';
    expect(rustAsciiCaseProblem(site), isNull);
    expect(
      rustAsciiCaseProblem(
        site.replaceFirst('.flat_map(char::to_lowercase)', ''),
      ),
      isNotNull,
    );
  });

  test(
    'sans lettre accentuée, ou dans un commentaire ou une chaîne : rien',
    () {
      for (final code in [
        'fn f(s: &str) -> String { s.to_ascii_lowercase() }\n',
        'fn f(c: char) -> char {\n    // \'é\' est géré ailleurs\n    c.to_ascii_lowercase()\n}\n',
        'fn f(s: &str) -> String {\n    let t = "pas \'é\' ici";\n    s.to_ascii_lowercase()\n}\n',
        // ß n'a pas de majuscule d'une lettre.
        'fn f(c: char) -> bool { c.to_ascii_lowercase() == \'ß\' }\n',
      ]) {
        expect(rustAsciiCaseProblem(code), isNull, reason: code);
      }
    },
  );

  test('les lignes du fichier d\'origine ne sont jamais visées', () {
    expect(
      rustAsciiCaseProblem(_written, old: _written.split('\n').toSet()),
      isNull,
    );
    expect(
      AgentRun.rustAsciiCaseHint('site/src/lib.rs', _written, before: _written),
      isNull,
    );
  });
}
