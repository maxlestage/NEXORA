import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/rust_check.dart';

// Ce que Pollinations a réellement écrit pour « ajoute compter_mots() dans
// site/src/contenu.rs, avec un test unitaire » : le même test deux fois.
const _written = '''
pub fn sans_etiquette(point: &str) -> String {
    point.to_string()
}

pub fn compter_mots(texte: &str) -> usize {
    texte.split_whitespace().count()
}

#[test]
fn test_compter_mots() {
    assert_eq!(compter_mots("Hello world"), 2);
}

#[test]
fn test_compter_mots() {
    assert_eq!(compter_mots("Hello world"), 2);
}
''';

void main() {
  test('le même test deux fois : signalé, avec les deux lignes', () {
    final error = rustDuplicateFnError(_written);
    expect(error, contains('ligne 15'));
    expect(error, contains('« fn test_compter_mots »'));
    expect(error, contains('ligne 10'));
    final hint = AgentRun.syntaxHint('site/src/contenu.rs', _written);
    expect(hint, contains('site/src/contenu.rs ne compilera pas'));
  });

  test('même nom dans des blocs différents : rien à dire', () {
    const ok = '''
struct A;
struct B;
impl A {
    pub fn new() -> Self { A }
}
impl B {
    pub fn new() -> Self { B }
}
fn aide() {}
#[cfg(test)]
mod tests {
    use super::*;
    fn aide() {}
    #[test]
    fn nouveau() { aide(); }
}
mod autre {
    #[test]
    fn nouveau() {}
}
''';
    expect(rustDuplicateFnError(ok), isNull);
  });

  test('variantes sous #[cfg(…)] et fonctions dans une macro', () {
    const cfg = '''
#[cfg(unix)]
fn chemin() -> &'static str { "/" }
#[cfg(not(unix))]
fn chemin() -> &'static str { "C:" }
#[cfg(feature = "a")] fn f() {}
#[cfg(not(feature = "a"))] fn f() {}
''';
    expect(rustDuplicateFnError(cfg), isNull);
    const macro = '''
macro_rules! deux {
    () => { fn x() {} };
    (b) => { fn x() {} };
}
cfg_digit!(
    fn serialize() {}
    fn serialize() {}
);
impl_simd! {
  fn shr() {}
  fn shr() {}
}
''';
    expect(rustDuplicateFnError(macro), isNull);
  });

  test('chaînes et commentaires ne comptent pas', () {
    const text = '''
// fn a() {}
fn a() {}
/* fn a() {} */
const S: &str = "fn a() {}";
const R: &str = r#"fn a() { "#;
const C: char = '{';
''';
    expect(rustDuplicateFnError(text), isNull);
    expect(rustDuplicateFnError('$text\nfn a() {}\n'), contains('ligne 8'));
  });
}
