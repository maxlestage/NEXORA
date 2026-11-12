import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const _cargo = '''
[package]
name = "nexora-site"

[lib]
name = "nexora_site"
''';

const _libRs = '''
pub mod contenu;
mod mouvement;
''';

const _before = '''
/// Le point sans son étiquette.
pub fn sans_etiquette(point: &str) -> String {
    point.to_string()
}
''';

// L'exemple réellement écrit par Pollinations pour « ajoute compter_mots()
// dans site/src/contenu.rs, avec un test » : le doctest ne compilait pas.
const _written = '''$_before
/// Compte le nombre de mots dans un texte.
///
/// # Exemple
/// ```rust
/// assert_eq!(compter_mots("Bonjour, monde! Ça va?"), 4);
/// ```
pub fn compter_mots(texte: &str) -> usize {
    texte.split_whitespace().filter(|s| !s.is_empty()).count()
}
''';

String? _hint(String path, String content, {String? before = _before}) =>
    AgentRun.rustDocTestHint(
      path,
      content,
      before: before,
      cargo: _cargo,
      libRs: _libRs,
    );

void main() {
  test('exemple de doc sans import : signalé, avec le bon import', () {
    final hint = _hint('site/src/contenu.rs', _written);
    expect(hint, contains('doctest'));
    expect(hint, contains('« compter_mots() »'));
    expect(hint, contains('« use nexora_site::contenu::compter_mots; »'));
    expect(hint, contains('#[cfg(test)] mod tests'));
    expect(hint, contains('ligne 9'));
  });

  test('exemple qui importe la bibliothèque : rien à dire', () {
    final ok = _written.replaceFirst(
      '/// assert_eq!',
      '/// use nexora_site::contenu::compter_mots;\n/// assert_eq!',
    );
    expect(_hint('site/src/contenu.rs', ok), isNull);
    // Import caché (« # use … ») : compilé aussi.
    final hidden = _written.replaceFirst(
      '/// assert_eq!',
      '/// # use nexora_site::contenu::compter_mots;\n/// assert_eq!',
    );
    expect(_hint('site/src/contenu.rs', hidden), isNull);
  });

  test('blocs non compilés et texte : jamais visés', () {
    for (final fence in ['```ignore', '```text', '```compile_fail', '```sh']) {
      final c = _written.replaceFirst('```rust', fence);
      expect(_hint('site/src/contenu.rs', c), isNull, reason: fence);
    }
  });

  test('exemple déjà présent avant : pas d\'alerte', () {
    expect(_hint('site/src/contenu.rs', _written, before: _written), isNull);
  });

  test('module privé : pas d\'import proposé, test unitaire à la place', () {
    final hint = _hint('site/src/mouvement.rs', _written);
    expect(hint, contains('n\'est pas public'));
    expect(hint, isNot(contains('use nexora_site::mouvement')));
    expect(hint, contains('#[cfg(test)] mod tests'));
  });

  test('fichiers hors src/, tests/ et lib.rs racine', () {
    expect(_hint('site/tests/contenu.rs', _written), isNull);
    expect(_hint('site/build.rs', _written), isNull);
    expect(_hint('site/src/main.rs', _written), isNull);
    expect(_hint('site/src/bin/outil.rs', _written), isNull);
    final root = _hint('site/src/lib.rs', _written);
    expect(root, contains('« use nexora_site::compter_mots; »'));
  });

  test('l\'exemple définit lui-même la fonction, ou appelle std', () {
    const own = '''
/// ```
/// fn compter_mots(t: &str) -> usize { t.len() }
/// assert_eq!(compter_mots("ab"), 2);
/// ```
pub fn compter_mots(texte: &str) -> usize {
    texte.len()
}
''';
    expect(_hint('site/src/contenu.rs', own, before: null), isNull);
    const std = '''
/// ```
/// let v = vec![1, 2];
/// assert_eq!(v.len(), 2);
/// ```
pub fn compter_mots(texte: &str) -> usize {
    texte.len()
}
''';
    expect(_hint('site/src/contenu.rs', std, before: null), isNull);
  });

  test('façade d\'un autre crate (use futures::…) : on ne juge pas', () {
    const facade = '''
/// ```
/// use futures::future::poll_fn;
/// let f = poll_fn(lire);
/// ```
pub fn poll_fn() {}
''';
    expect(_hint('x/src/future/poll_fn.rs', facade, before: null), isNull);
  });
}
