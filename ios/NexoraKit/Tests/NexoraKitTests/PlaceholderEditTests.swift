import Foundation
import Testing
@testable import NexoraKit

/// Un commentaire « // ... existing code » à la place du code gardé (port de Flutter 2.2.91).
@Suite("Agent : commentaire qui tient la place du code existant")
struct PlaceholderEditTests {
    static let mainRs = """
    async fn robots(_req: Request) -> String {
        "User-agent: *".to_string()
    }

    async fn telecharger(_req: Request) -> Page {
        let plateformes = section().class("section");
        page("Télécharger", vec![plateformes.into()])
    }

    """

    @Test("repéré dans le texte ajouté")
    func spotted() {
        for l in [
            "    // ... existing code", "// …", "    // ... other routes", "// existing code unchanged",
            "// rest of the file", "  # ... rest of the tests", "/* ... */", "<!-- ... -->",
            "// reste du code inchangé", "// ... code existant", "    // (existing tests here)",
        ] {
            #expect(placeholderLine("fn a() {\n\(l)\n}", "fn a() {", "") == l, "\(l)")
        }
    }

    @Test("les vrais commentaires ne sont pas visés")
    func realComments() {
        for l in [
            "// Lit la première version de nouveautes.md.", "/// ...", "//! ...", "#[cfg(test)]",
            "# Previous versions", "// Other platforms are handled below.",
            "// The existing value is kept when the key is missing.", "    let rest = '...';", "    // TODO",
        ] {
            #expect(placeholderLine("fn a() {\n\(l)\n}", "", "") == nil, "\(l)")
        }
    }

    @Test("déjà dans le fichier ou dans old : gardé tel quel")
    func known() {
        let line = "    // ... existing code"
        #expect(placeholderLine("x\n\(line)", line, "") == nil)
        #expect(placeholderLine("x\n\(line)", "x", "a\n\(line)\nb") == nil)
    }

    @Test("cas réel : la modification est refusée, le fichier reste intact")
    @MainActor
    func realCase() async throws {
        let head = "async fn telecharger(_req: Request) -> Page {"
        let version = "async fn version(_req: Request) -> String {\n    \"2.2.90\".to_string()\n}"
        let llm = ScriptLLM([
            act(["tool": "edit_file", "args": [
                "path": "site/src/main.rs", "old": head,
                "new": "\(head)\n    // ... existing code\n}\n\n\(version)",
            ]]),
            act(["tool": "edit_file", "args": ["path": "site/src/main.rs", "old": head, "new": "\(version)\n\n\(head)"]]),
            act(["tool": "finish", "args": ["summary": "Route /version ajoutée"]]),
        ])
        let run = makeRun(llm, hub: repoHub(["site/src/main.rs": Self.mainRs]), task: "Ajoute une route /version", checks: false)
        await run.run()
        #expect(run.summary == "Route /version ajoutée")
        #expect(llm.prompt(1).contains("tient la place de code existant"))
        let after = try #require(run.draft("site/src/main.rs"))
        #expect(!after.contains("existing code"))
        #expect(after.contains("async fn version"))
        #expect(after.contains("\(head)\n    let plateformes"))
    }

    @Test("sans effet sur les commentaires des fichiers du dépôt")
    func repoFiles() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var seen = 0
        var hits: [String] = []
        for dir in ["ios/NexoraKit/Sources", "ios/Nexora", "app/lib", "site/src"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where ["swift", "dart", "rs"].contains(url.pathExtension) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                seen += 1
                // Chaque fichier, vu comme un ajout dans un fichier vide.
                if let l = placeholderLine(text, "", "") { hits.append("\(url.lastPathComponent): \(l)") }
            }
        }
        #expect(seen > 50)
        #expect(hits.isEmpty, "\(hits)")
    }
}
