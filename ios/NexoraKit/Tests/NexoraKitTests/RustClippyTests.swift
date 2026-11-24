import Foundation
import Testing
@testable import NexoraKit

/// Les tournures que `cargo clippy -- -D warnings` refuse (port de Flutter 2.2.102).
@Suite("Agent : avertissements clippy")
@MainActor
struct RustClippyTests {
    @Test("arrondi au supérieur : le cas de l'essai réel est signalé, avec la correction")
    func divCeilRealCase() {
        let code = """
        pub fn temps_de_lecture(texte: &str) -> u32 {
            let mots = texte.split_whitespace().count() as u32;
            let minutes = (mots + 199) / 200;
            if minutes == 0 { 1 } else { minutes }
        }

        """
        let found = rustClippyProblems(code)
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("ligne 3 :") == true)
        #expect(found.first?.contains("manual_div_ceil") == true)
        #expect(found.first?.contains("mots.div_ceil(200)") == true)
    }

    @Test("arrondi au supérieur : les formes que clippy refuse sont toutes vues")
    func divCeilForms() {
        for (expr, fix) in [
            ("(v.len() + 7) / 8", "v.len().div_ceil(8)"),
            ("(199 + m) / 200", "m.div_ceil(200)"),
            ("(m + n - 1) / n", "m.div_ceil(n)"),
            ("(m + (n - 1)) / n", "m.div_ceil(n)"),
            ("(x + 99) / 100 * 3", "x.div_ceil(100)"),
            ("(x + 1_999) / 2_000", "x.div_ceil(2000)"),
        ] {
            let found = rustClippyProblems("    let r = \(expr);\n")
            #expect(found.count == 1, "\(expr)")
            #expect(found.first?.contains(fix) == true, "\(expr)")
        }
    }

    @Test("arrondi au supérieur : ce que clippy accepte n'est jamais signalé")
    func divCeilAccepted() {
        for code in [
            // Une valeur signée : div_ceil n'existe pas (clippy se tait).
            "fn b(m: i32) -> i32 { (m + 199) / 200 }",
            "let m = n as i64;\nlet r = (m + 199) / 200;",
            // Pas un arrondi : le nombre ajouté n'est pas le diviseur moins un.
            "let r = (m + 100) / 200;",
            "let r = (m + 1) / 1;",
            // « 3 * (x + 99) / 100 » se calcule (3 * (x + 99)) / 100.
            "let r = 3 * (x + 99) / 100;",
            // Un appel de fonction, des décimaux.
            "let r = f(m + 199) / 200;",
            "let r = (m + 1.0) / 2.0;",
            // Un diviseur différent.
            "let r = (m + n - 1) / k;",
            // Dans un commentaire ou un texte.
            "// let r = (m + 199) / 200;",
            "let s = \"(m + 199) / 200\";",
        ] {
            #expect(rustClippyProblems(code).isEmpty, "\(code)")
        }
    }

    @Test("intervalle : les formes que clippy refuse sont toutes vues")
    func rangeForms() {
        for (expr, fix) in [
            ("x >= 1 && x <= 10", "(1..=10).contains(&x)"),
            ("x >= 1 && x < 10", "(1..10).contains(&x)"),
            ("1 <= x && x <= 10", "(1..=10).contains(&x)"),
            ("x <= 10 && x >= 1", "(1..=10).contains(&x)"),
            ("x >= -1 && x <= 1", "(-1..=1).contains(&x)"),
            ("x >= 0.0 && x < 1.0", "(0.0..1.0).contains(&x)"),
            ("x < 1 || x > 10", "!(1..=10).contains(&x)"),
            ("x < 1 || x >= 10", "!(1..10).contains(&x)"),
            ("y && x >= 1 && x <= 10", "(1..=10).contains(&x)"),
            ("y || x < 1 || x > 10", "!(1..=10).contains(&x)"),
        ] {
            let found = rustClippyProblems("fn f() -> bool { \(expr) }\n")
            #expect(found.count == 1, "\(expr)")
            #expect(found.first?.contains("manual_range_contains") == true, "\(expr)")
            #expect(found.first?.contains(fix) == true, "\(expr)")
        }
    }

    @Test("intervalle : ce que clippy accepte n'est jamais signalé")
    func rangeAccepted() {
        for code in [
            // Une borne exclue en bas, des bornes variables, un champ.
            "fn j(x: i32) -> bool { x > 1 && x <= 10 }",
            "fn g(x: i32) -> bool { x >= lo && x < hi }",
            "fn d(s: &S) -> bool { s.v >= 1 && s.v <= 3 }",
            // Deux variables différentes.
            "fn d(x: i32, y: i32) -> bool { x >= 1 && y <= 3 }",
            // Les && sont calculés d'abord : pas d'intervalle.
            "fn j(x: i32, y: bool) -> bool { x < 1 || x > 10 && y }",
            "fn j(x: i32, y: bool) -> bool { y && x < 1 || x > 10 }",
            // contains n'est pas utilisable dans une const fn.
            "pub const fn h(x: i32) -> bool { x >= 1 && x <= 10 }",
            "const OK: bool = N >= 1 && N <= 10;",
        ] {
            #expect(rustClippyProblems(code).isEmpty, "\(code)")
        }
    }

    @Test("les lignes du fichier d'origine ne sont jamais visées")
    func originalLinesIgnored() {
        let before = "fn a(m: u32) -> u32 { (m + 7) / 8 }\n"
        #expect(AgentRun.rustClippyHint("src/lib.rs", before, before: before) == nil)
        let hint = AgentRun.rustClippyHint("src/lib.rs", before + "fn b(m: u32) -> u32 { (m + 3) / 4 }\n",
                                           before: before) ?? ""
        #expect(hint.contains("-D warnings"))
        #expect(hint.contains("ligne 2"))
        #expect(hint.contains("m.div_ceil(4)"))
        #expect(!hint.contains("div_ceil(8)"))
    }

    @Test("un même avertissement n'est donné qu'une fois")
    func warnedOnce() {
        var skip: Set<String> = []
        let code = "fn b(m: u32) -> u32 { (m + 3) / 4 }\n"
        #expect(AgentRun.rustClippyHint("a.rs", code, skip: &skip) != nil)
        #expect(AgentRun.rustClippyHint("a.rs", code, skip: &skip) == nil)
        // Même si la ligne a bougé.
        #expect(AgentRun.rustClippyHint("a.rs", "\n" + code, skip: &skip) == nil)
        // Un autre fichier est prévenu.
        #expect(AgentRun.rustClippyHint("b.rs", code, skip: &skip) != nil)
        #expect(AgentRun.rustClippyHint("b.dart", code) == nil)
    }

    @Test("seule une CI qui refuse les avertissements de clippy compte")
    func deniesWarnings() {
        #expect(AgentRun.clippyDeniesWarnings("- run: cargo clippy --all-targets -- -D warnings"))
        #expect(AgentRun.clippyDeniesWarnings("env:\n  RUSTFLAGS: -Dwarnings\n- run: cargo clippy"))
        #expect(!AgentRun.clippyDeniesWarnings("- run: cargo clippy"))
        #expect(!AgentRun.clippyDeniesWarnings("- run: cargo test"))
    }

    func session(_ files: [String: String], writes: Int = 2) async -> ScriptLLM {
        let code = "pub fn temps(m: u32) -> u32 {\n    (m + 199) / 200\n}\n"
        // La seconde écriture garde la même ligne fautive, un peu plus bas.
        let llm = ScriptLLM((0..<writes).map { k in
            act(["tool": "write_file", "args": ["path": "site/src/lib.rs",
                                                "content": String(repeating: "// note\n", count: k) + code]])
        })
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        var all = files
        all["site/Cargo.toml"] = "[package]\nname = \"site\"\n"
        let run = makeRun(llm, hub: repoHub(all), repo: "NEXORA", branch: "master",
                          task: "Ajoute temps() dans site/src/lib.rs", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return llm
    }

    @Test("CI avec clippy -D warnings : prévenu dès l'écriture, une seule fois")
    func inSession() async {
        let ci = "jobs:\n  site:\n    steps:\n      - run: cargo clippy -- -D warnings\n"
        let llm = await session([".github/workflows/ci.yml": ci])
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(llm.last(1).contains("m.div_ceil(200)"))
        // La même ligne réécrite ne répète pas l'alerte.
        #expect(llm.last(2).contains("enregistré en brouillon"))
        #expect(!llm.last(2).contains("div_ceil"))
    }

    @Test("CI sans clippy : aucune alerte")
    func noClippy() async {
        let llm = await session([".github/workflows/ci.yml": "steps:\n  - run: cargo test\n"], writes: 1)
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(!llm.last(1).contains("div_ceil"))
    }
}
