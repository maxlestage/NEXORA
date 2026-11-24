import Foundation
import Testing
@testable import NexoraKit

/// edit_file quand le modèle renvoie les « \n » d'une chaîne du fichier comme de
/// vrais retours à la ligne (port de Flutter 2.2.83).
@Suite("Agent : edit_file et les « \\n » des chaînes")
struct StringNewlineEditTests {
    /// La fonction robots() du site, telle qu'elle est dans site/src/main.rs.
    static let robots = #"""
    async fn sitemap(_req: Request) -> Response {
        Response::new()
    }

    async fn robots(_req: Request) -> String {
        format!(
            "User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n",
            site_url()
        )
    }

    fn app() -> App {
        let mut app = App::new();
    }

    """#

    /// Ce que le modèle envoie : le JSON « \n » décodé en vrai retour.
    static let old =
        "async fn robots(_req: Request) -> String {\n"
        + "    format!(\n"
        + "        \"User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n\",\n"
        + "        site_url()\n"
        + "    )\n"
        + "}\n"

    @Test("un vrai retour à la ligne dans une chaîne redevient « \\n »")
    func escapes() {
        #expect(escapeStringNewlines("let s = \"a\nb\";") == #"let s = "a\nb";"#)
        #expect(escapeStringNewlines("final s = 'a\nb';") == #"final s = 'a\nb';"#)
        #expect(escapeStringNewlines("let s = \"x \\(f(\"y\")) a\nb\"") == #"let s = "x \(f("y")) a\nb""#)
    }

    @Test("commentaires, apostrophes, chaînes brutes ou sur plusieurs lignes, durées de vie, caractères : intacts")
    func untouched() {
        let samples = [
            "fn f() {\n    g(\"x\");\n}\n",
            "// l'agent écrit \"ici\nfn f() {}",
            "final t = '''\nligne\n''';",
            "final t = \"\"\"\nligne\n\"\"\";",
            "let t = r#\"\n\"#;",
            "let t = r\"\n\";",
            "let t = #\"a \"b\"\n\"#",
            "fn f<'a>(x: &'a str) -> &'a str {\n    x\n}",
            "static S: &'static str = \"x\";\nfn g() {}",
            "// d'abord\nlet x = 1; // l'autre\nlet y = 2;",
            "write(\".nojekyll\", b\"\")?;\nlet x = 1;",
            "if c == b'\"' {\n    n += 1;\n}",
            "final t = '${ok ? '\\nL\\'agent' : ''}';\nfinal u = 2;",
            "let o = \"${\"\nlet p = \"${{\"\nlet z = '${'z' * 3}'\n",
        ]
        for s in samples {
            #expect(escapeStringNewlines(s) == s, "\(s)")
        }
    }

    @Test("sans effet sur les fichiers Swift, Dart et Rust du dépôt")
    func repoFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var seen = 0
        var changed: [String] = []
        for dir in ["ios/NexoraKit/Sources", "ios/Nexora", "app/lib", "app/test", "site/src"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                let ext = url.pathExtension
                guard ["swift", "dart", "rs"].contains(ext), url.lastPathComponent != "contenu.rs",
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if escapeStringNewlines(text) != text { changed.append(url.lastPathComponent) }
                seen += 1
            }
        }
        #expect(changed.isEmpty, "\(changed)")
        #expect(seen > 100)
    }

    @Test("le passage est trouvé et la route ajoutée, « \\n » gardés")
    func robotsRoute() {
        let added = "\nasync fn version(_req: Request) -> String {\n"
            + "    format!(\"{}\n\", versions()[0].numero)\n"
            + "}\n"
        let (out, summary) = applyEdit(Self.robots, Self.old, Self.old + added)
        #expect(out != nil, "\(summary)")
        #expect(out?.contains(#""User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n""#) == true)
        #expect(out?.contains(#"format!("{}\n", versions()[0].numero)"#) == true)
        #expect(out?.contains("async fn version(_req: Request) -> String {\n") == true)
        #expect(out?.contains("fn app() -> App {") == true)
        #expect(summary.contains("des chaînes gardés"))
    }

    @Test("un passage vraiment absent reste refusé")
    func absent() {
        let (out, why) = applyEdit(Self.robots, "async fn humans() {\n    \"a\nb\"\n}", "x")
        #expect(out == nil)
        #expect(why.contains("passage introuvable"))
    }

    @Test("une vraie chaîne sur plusieurs lignes, ou un passage exact : modifiés comme avant")
    func unchanged() {
        let yaml = "let y = \"name: CI\non: push\n\";\nfn f() {}\n"
        let (out, summary) = applyEdit(yaml, "name: CI\non: push", "name: Tests\non: push")
        #expect(out == "let y = \"name: Tests\non: push\n\";\nfn f() {}\n")
        #expect(summary == "1 remplacement")
        let (out2, summary2) = applyEdit(Self.robots, "fn app() -> App {", "fn app() -> App {\n    // routes")
        #expect(out2?.contains("fn app() -> App {\n    // routes") == true)
        #expect(summary2 == "1 remplacement")
    }
}
