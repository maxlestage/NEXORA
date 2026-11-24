import Foundation
import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.97 : une fonction Rust définie deux fois dans le même bloc
/// est signalée dès l'écriture.
@Suite("Agent : fonction Rust écrite deux fois")
@MainActor
struct RustDuplicateFnTests {
    // Ce que le modèle a réellement écrit pour « ajoute compter_mots() dans
    // site/src/contenu.rs, avec un test unitaire » : le même test deux fois.
    static let written = """
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

    """

    @Test("le même test deux fois : signalé, avec les deux lignes")
    func duplicate() {
        let error = rustDuplicateFnError(Self.written) ?? ""
        #expect(error.contains("ligne 15"))
        #expect(error.contains("« fn test_compter_mots »"))
        #expect(error.contains("ligne 10"))
        let hint = AgentRun.syntaxHint("site/src/contenu.rs", Self.written) ?? ""
        #expect(hint.contains("site/src/contenu.rs ne compilera pas"))
    }

    @Test("même nom dans des blocs différents : rien à dire")
    func differentBlocks() {
        let ok = """
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

        """
        #expect(rustDuplicateFnError(ok) == nil)
    }

    @Test("variantes sous #[cfg(…)] et fonctions dans une macro")
    func cfgAndMacros() {
        let cfg = """
        #[cfg(unix)]
        fn chemin() -> &'static str { "/" }
        #[cfg(not(unix))]
        fn chemin() -> &'static str { "C:" }
        #[cfg(feature = "a")] fn f() {}
        #[cfg(not(feature = "a"))] fn f() {}

        """
        #expect(rustDuplicateFnError(cfg) == nil)
        let macro = """
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

        """
        #expect(rustDuplicateFnError(macro) == nil)
    }

    @Test("chaînes et commentaires ne comptent pas")
    func stringsAndComments() {
        let text = """
        // fn a() {}
        fn a() {}
        /* fn a() {} */
        const S: &str = "fn a() {}";
        const R: &str = r#"fn a() { "#;
        const C: char = '{';

        """
        #expect(rustDuplicateFnError(text) == nil)
        #expect(rustDuplicateFnError(text + "\nfn a() {}\n")?.contains("ligne 8") == true)
    }

    @Test("le code sans commentaires garde la longueur et les lignes")
    func bareCode() {
        let code = "let c = '\\u{e9}'; // fn x()\nlet s = \"a\\\"b\"; 'a: loop {}\n"
        let bare = rustBareCode(code)
        #expect(bare.count == code.utf16.count)
        let text = String(utf16CodeUnits: bare, count: bare.count)
        #expect(!text.contains("fn x"))
        #expect(text.contains("'a: loop {}"))
        #expect(text.components(separatedBy: "\n").count == 3)
    }
}
