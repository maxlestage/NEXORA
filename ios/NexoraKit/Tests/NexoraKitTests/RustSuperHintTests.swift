import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.94 : un test d'intégration Rust (tests/) avec `super::`
/// est signalé dès son écriture.
@Suite struct RustSuperHintTests {
    let cargo = "[package]\nname = \"nexora-site\"\n\n[lib]\nname = \"nexora_site\"\n"

    // Le test réellement écrit par un modèle pour « ajoute un test » de nature().
    let written = """
    // Tests for contenu module
    use super::*;

    #[test]
    fn test_retired_nature() {
        let (label, css) = nature("Retiré : point important");
        assert_eq!(label, "Retiré");
    }
    """

    @Test func superEnTeteSignale() throws {
        let hint = try #require(AgentRun.rustTestHint("site/tests/contenu.rs", written, cargo: cargo))
        #expect(hint.contains("« use super::*; » ne compilera pas"))
        #expect(hint.contains("« use nexora_site::… »"))
        #expect(hint.contains("#[cfg(test)] mod tests"))
    }

    @Test func modTestsSansBibliotheque() throws {
        let content = "#[cfg(test)]\nmod tests {\n    use super::*;\n\n    #[test]\n    fn retire() {\n"
            + "        assert_eq!(nature(\"Retiré : x\").0, \"Retiré\");\n    }\n}\n"
        let hint = try #require(AgentRun.rustTestHint("site/tests/contenu.rs", content, cargo: cargo))
        #expect(hint.contains("n'importe jamais la bibliothèque"))
        #expect(hint.contains("« use nexora_site::… »"))
    }

    @Test func ceQuiCompileNestPasSignale() {
        #expect(AgentRun.rustTestHint("site/tests/contenu.rs",
            "use nexora_site::contenu::nature;\n\nmod tests {\n    use super::*;\n\n"
            + "    #[test]\n    fn a() {\n        nature(\"x\");\n    }\n}\n", cargo: cargo) == nil)
        #expect(AgentRun.rustTestHint("tests/outil.rs",
            "mod aide {\n    pub fn un() -> u8 {\n        1\n    }\n}\n"
            + "mod cas {\n    use super::aide::un;\n    #[test]\n    fn a() {\n        assert_eq!(un(), 1);\n    }\n}\n") == nil)
        #expect(AgentRun.rustTestHint("tests/cli.rs",
            "mod cas {\n    use super::*;\n    use std::process::Command;\n}\n", cargo: cargo) == nil)
        #expect(AgentRun.rustTestHint("tests/test_buf.rs",
            "macro_rules! buf_tests {\n    ($m:ident) => {\n        use super::*;\n    };\n}\n", cargo: cargo) == nil)
        #expect(AgentRun.rustTestHint("src/contenu.rs", written) == nil)
        #expect(AgentRun.rustTestHint("tests/a.rs",
            "// use super::*;\nuse nexora_site::a;\n#[test]\nfn t() {\n    let _ = \"super::x {\";\n    a();\n}\n",
            cargo: cargo) == nil)
    }
}
