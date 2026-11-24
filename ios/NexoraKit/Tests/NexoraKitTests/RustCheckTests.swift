import Foundation
import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.87 : le code Rust écrit par l'agent est relu (accolade,
/// parenthèse ou crochet en trop ou jamais fermé, chaîne jamais fermée).
@Suite("Agent : relecture du Rust")
@MainActor
struct RustCheckTests {
    // slug() du site, tel qu'il est sur GitHub.
    static let orig = """
    /// Le nom de fichier d'un agent : minuscules, tirets.
    pub fn slug(nom: &str) -> String {
        let mut out = String::new();
        for c in nom.trim().chars() {
            let c = match c {
                'à' | 'â' | 'ä' => 'a',
                'é' | 'è' | 'ê' | 'ë' => 'e',
                'ç' => 'c',
                c => c.to_ascii_lowercase(),
            };
            if c.is_ascii_alphanumeric() {
                out.push(c);
            } else if !out.ends_with('-') && !out.is_empty() {
                out.push('-');
            }
        }
        out
    }

    """

    // Essai réel : « old » ne couvrait que le début du match, « new » le récrivait
    // en entier ; les anciennes branches restaient derrière, avec une accolade de trop.
    static let old = """
            let c = match c {
                'à' | 'â' | 'ä' => 'a',
    """
    static let new = """
            let c = match c {
                'À' | 'Â' | 'Ä' | 'à' | 'â' | 'ä' => 'a',
                'É' | 'È' | 'Ê' | 'Ë' | 'é' | 'è' | 'ê' | 'ë' => 'e',
                'Ç' | 'ç' => 'c',
                c => c.to_ascii_lowercase(),
            }
    """
    static var broken: String { orig.replacingOccurrences(of: old, with: new) }
    static var good: String {
        orig.replacingOccurrences(of: "'é' | 'è'", with: "'É' | 'é' | 'è'")
    }

    @Test("le Rust valide n'est jamais signalé")
    func valid() {
        #expect(rustSyntaxError(Self.orig) == nil)
        for ok in [
            "fn f<'a>(x: &'a str) -> &'a str { x }",
            "let c = '{'; let d = '}'; let e = '\\''; let f = '\\\\';",
            "let u = '\\u{e9}'; let b = b'['; let g = '🦀';",
            "let s = \"a { b ( [ \\\" c\";",
            "let r = r#\"brut \"{\" ([\"#; let q = br\"x}\";",
            "let m = r##\"un \"# dedans { \"##;",
            "'outer: loop { break 'outer; }",
            "// une accolade { dans un commentaire\nfn g() {}",
            "/* imbriqué /* { */ toujours ( */\nfn h() {}",
            "let t = \"sur\nplusieurs { lignes\";",
            "fn r#type() {}",
            "fn k() {} static S: &str = \"\\\\\";",
        ] {
            #expect(rustSyntaxError(ok) == nil, "\(ok)")
        }
        // Les vrais fichiers Rust du dépôt ne sont jamais signalés.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../site").standardized
        var seen = 0
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension == "rs" && !u.path.contains("/target/") {
                guard let s = try? String(contentsOf: u, encoding: .utf8) else { continue }
                seen += 1
                #expect(rustSyntaxError(s) == nil, "\(u.lastPathComponent)")
            }
        }
        #expect(seen > 0)
    }

    @Test("les erreurs certaines sont repérées, avec la ligne et le début du décalage")
    func errors() throws {
        let e = try #require(rustSyntaxError(Self.broken))
        #expect(e.contains("ferme quelque chose qui n'a jamais été ouvert"))
        #expect(e.hasPrefix("ligne 22 "))
        #expect(e.contains("le décalage commence sans doute ligne 14 (« }; »), alignée autrement que la ligne 4"))
        #expect(rustSyntaxError("fn f() {\n    g(1];\n}\n")?.contains("« ] »") == true)
        #expect(rustSyntaxError("fn f() {\n    g(1);\n")?.contains("jamais fermé") == true)
        #expect(rustSyntaxError("let s = \"sans fin;\n")?.contains("chaîne") == true)
        #expect(rustSyntaxError("let s = r#\"sans fin\";\n")?.contains("\"#") == true)
    }

    @Test("Dart et Rust : chacun avec sa relecture")
    func hints() {
        #expect(AgentRun.syntaxHint("site/src/lib.rs", Self.orig) == nil)
        #expect(AgentRun.syntaxHint("site/src/lib.rs", Self.broken)?.contains("site/src/lib.rs ne compilera pas, ligne 22") == true)
        #expect(AgentRun.syntaxHint("notes.md", Self.broken) == nil)
        #expect(AgentRun.dartSyntaxHint("site/src/lib.rs", Self.broken) == nil)
    }

    func rustRun(_ replies: [String]) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies)
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let hub = repoHub(["site/Cargo.toml": "[package]\nname = \"site\"\n", "site/src/lib.rs": Self.orig])
        let run = makeRun(llm, hub: hub, repo: "NEXORA", branch: "master",
                          task: "Dans le site, slug() ignore les majuscules accentuées", checks: false)
        run.specs.append("déjà compris")
        return (run, llm)
    }

    func edit(_ old: String, _ new: String) -> String {
        "```json\n" + LooseJSON.string(["tool": "edit_file", "args": ["path": "site/src/lib.rs", "old": old, "new": new]]) + "\n```"
    }

    func write(_ content: String) -> String {
        "```json\n" + LooseJSON.string(["tool": "write_file", "args": ["path": "site/src/lib.rs", "content": content]]) + "\n```"
    }

    @Test("edit_file qui casse le Rust : prévenu tout de suite, et finish refusé tant que ce n'est pas corrigé")
    func inSession() async {
        let finish = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fait\"}}\n```"
        let (run, llm) = rustRun([
            edit(Self.old, Self.new), finish, write(Self.good),
            "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"corrigé\"}}\n```",
        ])
        await run.run()
        let sent = (0..<llm.count).map { llm.last($0) }
        #expect(sent.contains { $0.contains("site/src/lib.rs ne compilera pas, ligne 22") })
        #expect(sent.contains { $0.contains("Tu ne peux pas terminer") })
        #expect(run.summary == "corrigé")
        #expect(rustSyntaxError(run.draft("site/src/lib.rs") ?? "x {") == nil)
    }

    @Test("une modification correcte ne déclenche rien")
    func goodEdit() async {
        let (run, llm) = rustRun([
            edit("'é' | 'è'", "'É' | 'é' | 'è'"),
            "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fait\"}}\n```",
        ])
        await run.run()
        let sent = (0..<llm.count).map { llm.last($0) }
        #expect(!sent.contains { $0.contains("ne compilera pas") || $0.contains("Tu ne peux pas terminer") })
        #expect(run.summary == "fait")
    }
}
