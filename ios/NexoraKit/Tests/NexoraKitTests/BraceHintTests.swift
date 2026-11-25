import Foundation
import Testing
@testable import NexoraKit

/// Port de brace_hint_test.dart (Flutter 2.2.107) : un test collé au milieu
/// d'un autre, dont la fin reste dehors.
@Suite("Agent : accolade fermée trop tôt")
struct BraceHintTests {
    static let rust = [
        "#[cfg(test)]", "mod tests {", "    #[test]", "    fn iles() {",
        "        let accueil = page();", "    }", "", "    #[test]", "    fn version() {",
        "        assert_eq!(v(), \"1\");", "    }", "        for ile in [\"a\", \"b\"] {",
        "            assert!(accueil.contains(ile));", "        }", "    }", "}", "",
    ].joined(separator: "\n")

    static let dart = [
        "void main() {", "  test('a', () {", "    final x = 1;", "  });", "}",
        "    expect(x, 1);", "    if (x > 0) {", "      print(x);", "    }", "  });", "}", "",
    ].joined(separator: "\n")

    @Test("Rust : la ligne laissée hors de sa fonction est désignée")
    func rustDesigneLaLigneHorsDeSaFonction() throws {
        let e = try #require(rustSyntaxError(Self.rust))
        #expect(e.hasPrefix("ligne 16 "))
        #expect(e.contains("le décalage commence sans doute ligne 12 (« for ile"))
        #expect(e.contains("la « } » de la ligne 11 juste avant"))
        // L'ancien indice (la dernière fermeture mal alignée) n'est plus donné.
        #expect(!e.contains("alignée autrement"))
    }

    @Test("Dart : la ligne laissée hors de sa fonction est désignée")
    func dartDesigneLaLigneHorsDeSaFonction() throws {
        let e = try #require(dartSyntaxError(Self.dart))
        #expect(e.contains("ferme quelque chose qui n'a jamais été ouvert"))
        #expect(e.contains("le décalage commence sans doute ligne 6 (« expect"))
        #expect(e.contains("la « } » de la ligne 5 juste avant"))
    }

    @Test("sans code orphelin, l'erreur reste la même")
    func sansCodeOrphelinLErreurResteLaMeme() throws {
        let e = try #require(rustSyntaxError("fn f() {\n    g();\n}\n}\n"))
        #expect(e.hasPrefix("ligne 4 "))
        #expect(!e.contains("plus indentée"))
        // L'indice d'alignement reste donné quand il n'y a pas de code orphelin.
        let a = try #require(rustSyntaxError("fn f() {\n    g(|| {\n        h();\n      });\n    });\n}\n"))
        #expect(a.contains("le décalage commence sans doute ligne 4"))
        #expect(a.contains("alignée autrement"))
        let d = try #require(dartSyntaxError("void f() {\n  g();\n}\n}\n"))
        #expect(!d.contains("plus indentée"))
    }

    @Test("le code valide n'est jamais signalé")
    func leCodeValideNEstJamaisSignale() {
        let fixed = Self.rust.replacingOccurrences(of: "    }\n        for", with: "        for")
        #expect(rustSyntaxError(fixed) == nil)
        // Suites d'expression et else après une « } » seule : du code normal.
        let ok = "fn f() {\n    let x = if a {\n        1\n    }\n        + 2;\n    match y {\n        _ => {}\n    }\n}\n"
        #expect(rustSyntaxError(ok) == nil)
        // Une accolade dans une chaîne ou une interpolation ne compte pas.
        let e = dartSyntaxError("void f() {\n  final s = '${x\n}';\n}\n}\n") ?? ""
        #expect(!e.contains("plus indentée"))
    }
}
