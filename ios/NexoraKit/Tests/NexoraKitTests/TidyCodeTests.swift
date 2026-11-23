import Testing
@testable import NexoraKit

/// Lignes vides en trop dans le Rust et le Dart écrits par l'agent (port de
/// Flutter 2.2.77, tidy_code_test.dart).
@Suite("Agent : lignes vides en trop dans le code")
struct TidyCodeTests {
    @Test("Rust : deux lignes vides ramenées à une, fin de fichier propre")
    func rust() {
        let before = "pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n"
        let agent = "pub const A: u8 = 1;\n\n\n/// Compte.\npub fn n() -> usize {\n"
            + "    0\n}\n\n\n#[cfg(test)]\nmod t {}\n\n"
        #expect(tidyCode("site/src/contenu.rs", agent, before: before)
            == "pub const A: u8 = 1;\n\n/// Compte.\npub fn n() -> usize {\n"
            + "    0\n}\n\n#[cfg(test)]\nmod t {}\n")
    }

    @Test("Dart : entre deux fonctions et dans un test")
    func dart() {
        let agent = "import 'a.dart';\n\n\n\nString f() => '';\n  \n\nvoid main() {\n"
            + "  test('x', () {});\n}\n\n\n"
        #expect(tidyCode("app/lib/utils/texte.dart", agent)
            == "import 'a.dart';\n\nString f() => '';\n\nvoid main() {\n"
            + "  test('x', () {});\n}\n")
    }

    @Test("un long texte entre guillemets n'est pas touché")
    func strings() {
        let html = "const PAGE: &str = r#\"<p>Un</p>\n\n\n<p>Deux</p>\n\"#;\n"
            + "const T: &str = \"fin.\n\n\nsuite\";\n"
        #expect(tidyCode("site/src/pages.rs", html) == html)
    }

    @Test("un fichier d'origine déjà aéré est laissé tel quel")
    func looseOrigin() {
        let before = "fn a() {}\n\n\nfn b() {}\n\n"
        let agent = "fn a() {}\n\n\nfn b() {}\n\n\nfn c() {}\n\n"
        #expect(tidyCode("src/lib.rs", agent, before: before) == agent)
    }

    @Test("les autres fichiers ne changent pas")
    func others() {
        let md = "# Titre\n\n\n- point\n\n"
        #expect(tidyCode("README.md", md) == md)
        #expect(tidyCode("ci.yml", "a: 1\n\n\nb: 2\n") == "a: 1\n\n\nb: 2\n")
    }

    @Test("appliqué aux brouillons de l'agent (edit_file)")
    func withEdit() {
        let src = "pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n"
        let out = applyEdit(src, "pub const A: u8 = 1;\n", "pub const A: u8 = 1;\n\n\npub fn n() {}\n").0
        #expect(out != nil)
        #expect(tidyCode("src/lib.rs", out ?? "", before: src)
            == "pub const A: u8 = 1;\n\npub fn n() {}\n\n#[cfg(test)]\nmod t {}\n")
    }
}
