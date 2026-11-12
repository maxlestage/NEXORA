import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

const _cargo = '''
[package]
name = "nexora-site"

[lib]
name = "nexora_site"
''';

// Le test réellement écrit par Pollinations pour « fais reconnaître
// « Retiré » dans nature()… Ajoute un test » : il ne compilait pas.
const _written = '''
// Tests for contenu module
use super::*;

#[test]
fn test_retired_nature() {
    let (label, css) = nature("Retiré : point important");
    assert_eq!(label, "Retiré");
    assert_eq!(css, "tag-del");
}
''';

void main() {
  test('use super::* en tête d\'un test de tests/ : signalé', () {
    final hint = AgentRun.rustTestHint(
      'site/tests/contenu.rs',
      _written,
      cargo: _cargo,
    );
    expect(hint, contains('« use super::*; » ne compilera pas'));
    expect(hint, contains('« use nexora_site::… »'));
    expect(hint, contains('#[cfg(test)] mod tests'));
  });

  test('mod tests { use super::* } sans importer la bibliothèque', () {
    const content = '''
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retire() {
        assert_eq!(nature("Retiré : x").0, "Retiré");
    }
}
''';
    final hint = AgentRun.rustTestHint(
      'site/tests/contenu.rs',
      content,
      cargo: _cargo,
    );
    expect(hint, contains('n\'importe jamais la bibliothèque'));
    expect(hint, contains('« use nexora_site::… »'));
  });

  test('ce qui compile n\'est pas signalé', () {
    // La bibliothèque importée en tête, super::* dans un module du fichier.
    expect(
      AgentRun.rustTestHint(
        'site/tests/contenu.rs',
        'use nexora_site::contenu::nature;\n\n'
            'mod tests {\n    use super::*;\n\n'
            '    #[test]\n    fn a() {\n        nature("x");\n    }\n}\n',
        cargo: _cargo,
      ),
      isNull,
    );
    // Un module à soi, avec super:: dedans.
    expect(
      AgentRun.rustTestHint(
        'tests/outil.rs',
        'mod aide {\n    pub fn un() -> u8 {\n        1\n    }\n}\n'
            'mod cas {\n    use super::aide::un;\n'
            '    #[test]\n    fn a() {\n        assert_eq!(un(), 1);\n    }\n}\n',
      ),
      isNull,
    );
    // Le programme testé par sa commande.
    expect(
      AgentRun.rustTestHint(
        'tests/cli.rs',
        'mod cas {\n    use super::*;\n    use std::process::Command;\n}\n',
        cargo: _cargo,
      ),
      isNull,
    );
    // Dans une macro, super:: vise le module qui l'appelle (crate bytes).
    expect(
      AgentRun.rustTestHint(
        'tests/test_buf.rs',
        'macro_rules! buf_tests {\n    (\$m:ident) => {\n'
            '        use super::*;\n    };\n}\n',
        cargo: _cargo,
      ),
      isNull,
    );
    // Dans src/, super:: est juste.
    expect(AgentRun.rustTestHint('src/contenu.rs', _written), isNull);
    // Dans un texte ou un commentaire, ce n'est pas du code.
    expect(
      AgentRun.rustTestHint(
        'tests/a.rs',
        '// use super::*;\nuse nexora_site::a;\n'
            '#[test]\nfn t() {\n    let _ = "super::x {";\n    a();\n}\n',
        cargo: _cargo,
      ),
      isNull,
    );
  });
}
