import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/rust_check.dart';

void main() {
  group('rustClippyProblems — arrondi au supérieur (manual_div_ceil)', () {
    test('le cas de l\'essai réel est signalé, avec la correction', () {
      const code = '''
pub fn temps_de_lecture(texte: &str) -> u32 {
    let mots = texte.split_whitespace().count() as u32;
    let minutes = (mots + 199) / 200;
    if minutes == 0 { 1 } else { minutes }
}
''';
      final found = rustClippyProblems(code);
      expect(found, hasLength(1));
      expect(found.single, startsWith('ligne 3 :'));
      expect(found.single, contains('manual_div_ceil'));
      expect(found.single, contains('mots.div_ceil(200)'));
    });

    test('les formes que clippy refuse sont toutes vues', () {
      for (final (expr, fix) in [
        ('(v.len() + 7) / 8', 'v.len().div_ceil(8)'),
        ('(199 + m) / 200', 'm.div_ceil(200)'),
        ('(m + n - 1) / n', 'm.div_ceil(n)'),
        ('(m + (n - 1)) / n', 'm.div_ceil(n)'),
        ('(x + 99) / 100 * 3', 'x.div_ceil(100)'),
        ('(x + 1_999) / 2_000', 'x.div_ceil(2000)'),
      ]) {
        final found = rustClippyProblems('    let r = $expr;\n');
        expect(found, hasLength(1), reason: expr);
        expect(found.single, contains(fix), reason: expr);
      }
    });

    test('ce que clippy accepte n\'est jamais signalé', () {
      for (final code in [
        // Une valeur signée : div_ceil n'existe pas (clippy se tait).
        'fn b(m: i32) -> i32 { (m + 199) / 200 }',
        'let m = n as i64;\nlet r = (m + 199) / 200;',
        // Pas un arrondi : le nombre ajouté n'est pas le diviseur moins un.
        'let r = (m + 100) / 200;',
        'let r = (m + 1) / 1;',
        // « 3 * (x + 99) / 100 » se calcule (3 * (x + 99)) / 100.
        'let r = 3 * (x + 99) / 100;',
        // Un appel de fonction, une macro, des décimaux.
        'let r = f(m + 199) / 200;',
        'let r = (m + 1.0) / 2.0;',
        // Un diviseur différent.
        'let r = (m + n - 1) / k;',
        // Dans un commentaire ou un texte.
        '// let r = (m + 199) / 200;',
        'let s = "(m + 199) / 200";',
      ]) {
        expect(rustClippyProblems(code), isEmpty, reason: code);
      }
    });
  });

  group('rustClippyProblems — intervalle (manual_range_contains)', () {
    test('les formes que clippy refuse sont toutes vues', () {
      for (final (expr, fix) in [
        ('x >= 1 && x <= 10', '(1..=10).contains(&x)'),
        ('x >= 1 && x < 10', '(1..10).contains(&x)'),
        ('1 <= x && x <= 10', '(1..=10).contains(&x)'),
        ('x <= 10 && x >= 1', '(1..=10).contains(&x)'),
        ('x >= -1 && x <= 1', '(-1..=1).contains(&x)'),
        ('x >= 0.0 && x < 1.0', '(0.0..1.0).contains(&x)'),
        ('x < 1 || x > 10', '!(1..=10).contains(&x)'),
        ('x < 1 || x >= 10', '!(1..10).contains(&x)'),
        ('y && x >= 1 && x <= 10', '(1..=10).contains(&x)'),
        ('y || x < 1 || x > 10', '!(1..=10).contains(&x)'),
      ]) {
        final found = rustClippyProblems('fn f() -> bool { $expr }\n');
        expect(found, hasLength(1), reason: expr);
        expect(found.single, contains('manual_range_contains'), reason: expr);
        expect(found.single, contains(fix), reason: expr);
      }
    });

    test('ce que clippy accepte n\'est jamais signalé', () {
      for (final code in [
        // Une borne exclue en bas, des bornes variables, un champ.
        'fn j(x: i32) -> bool { x > 1 && x <= 10 }',
        'fn g(x: i32) -> bool { x >= lo && x < hi }',
        'fn d(s: &S) -> bool { s.v >= 1 && s.v <= 3 }',
        // Deux variables différentes.
        'fn d(x: i32, y: i32) -> bool { x >= 1 && y <= 3 }',
        // Les && sont calculés d'abord : pas d'intervalle.
        'fn j(x: i32, y: bool) -> bool { x < 1 || x > 10 && y }',
        'fn j(x: i32, y: bool) -> bool { y && x < 1 || x > 10 }',
        // contains n'est pas utilisable dans une const fn.
        'pub const fn h(x: i32) -> bool { x >= 1 && x <= 10 }',
        'const OK: bool = N >= 1 && N <= 10;',
      ]) {
        expect(rustClippyProblems(code), isEmpty, reason: code);
      }
    });
  });

  group('AgentRun.rustClippyHint', () {
    test('les lignes du fichier d\'origine ne sont jamais visées', () {
      const before = 'fn a(m: u32) -> u32 { (m + 7) / 8 }\n';
      expect(
        AgentRun.rustClippyHint('src/lib.rs', before, before: before),
        isNull,
      );
      final hint = AgentRun.rustClippyHint(
        'src/lib.rs',
        '${before}fn b(m: u32) -> u32 { (m + 3) / 4 }\n',
        before: before,
      );
      expect(hint, contains('-D warnings'));
      expect(hint, contains('ligne 2'));
      expect(hint, contains('m.div_ceil(4)'));
      expect(hint, isNot(contains('div_ceil(8)')));
    });

    test('un même avertissement n\'est donné qu\'une fois', () {
      final skip = <String>{};
      const code = 'fn b(m: u32) -> u32 { (m + 3) / 4 }\n';
      expect(AgentRun.rustClippyHint('a.rs', code, skip: skip), isNotNull);
      expect(AgentRun.rustClippyHint('a.rs', code, skip: skip), isNull);
      // Même si la ligne a bougé.
      expect(AgentRun.rustClippyHint('a.rs', '\n$code', skip: skip), isNull);
      // Un autre fichier est prévenu.
      expect(AgentRun.rustClippyHint('b.rs', code, skip: skip), isNotNull);
      expect(AgentRun.rustClippyHint('b.dart', code), isNull);
    });

    test('seule une CI qui refuse les avertissements de clippy compte', () {
      expect(
        AgentRun.clippyDeniesWarnings(
          '- run: cargo clippy --all-targets -- -D warnings',
        ),
        isTrue,
      );
      expect(
        AgentRun.clippyDeniesWarnings(
          'env:\n  RUSTFLAGS: -Dwarnings\n- run: cargo clippy',
        ),
        isTrue,
      );
      expect(AgentRun.clippyDeniesWarnings('- run: cargo clippy'), isFalse);
      expect(AgentRun.clippyDeniesWarnings('- run: cargo test'), isFalse);
    });
  });
}
