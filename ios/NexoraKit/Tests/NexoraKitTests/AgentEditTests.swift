import Foundation
import Testing
@testable import NexoraKit

/// edit_file et write_file : remplacements tolérants, mots coupés, commentaires
/// de documentation, ajouts à la fin, longs fichiers.
@Suite("Agent : modifications de fichiers")
struct AgentEditTests {
    static let css: String = {
        var s = ""
        for i in 0..<1800 { s += ".regle-\(i) { margin: 0 \(i)px; color: #123456; }\n" }
        s += ".atelier { display: grid; grid-template-columns: 320px 1fr; }\n"
        s += "/* FIN DU FICHIER */\n"
        return s
    }()

    @Test("long fichier : lu par plages, cherché, modifié sans perdre la fin")
    @MainActor
    func longFile() async throws {
        let big = Self.css
        #expect(big.len > 49000)
        let llm = ScriptLLM([
            act(["actions": [
                ["tool": "read_file", "args": ["path": "site/public/style.css"]],
                ["tool": "find_in_file", "args": ["path": "site/public/style.css", "pattern": "atelier"]],
            ]]),
            act(["thought": "Colonne fixe trop large sur mobile", "tool": "edit_file", "args": ["path": "site/public/style.css"]])
                + "\n```css\n.atelier { display: grid; grid-template-columns: 320px 1fr; }\n```\n"
                + "```css\n.atelier { display: grid; grid-template-columns: minmax(0, 320px) 1fr; }\n```",
            act(["tool": "finish", "args": ["summary": "Défilement corrigé"]]),
        ])
        let run = makeRun(llm, hub: repoHub(["site/public/style.css": big]), repo: "STRATYX", task: "Corrige le défilement horizontal", checks: false)
        await run.run()
        #expect(run.summary == "Défilement corrigé")
        let after = try #require(run.draft("site/public/style.css"))
        #expect(after.contains("minmax(0, 320px)"))
        #expect(after.contains("/* FIN DU FICHIER */"))
        #expect(after.contains(".regle-0 "))
        #expect(after.len > 49000)
        // La lecture d'un long fichier indique comment lire la suite.
        #expect(llm.prompt(1).contains("Lis la suite"))
        #expect(llm.prompt(1).contains("1801: .atelier"))
    }

    @Test("remplacement ciblé : passage unique, espaces de fin tolérés")
    func targeted() {
        #expect(applyEdit(Self.css, ".atelier", ".x").0 != nil)
        #expect(applyEdit("a\na\n", "a", "b").0 == nil) // pas unique
        #expect(applyEdit("a  \nb\n", "a\nb", "c").0 == "c\n") // espaces de fin
        #expect(applyEdit("x", "", "y").0 == "x\ny\n")
        #expect(applyEdit("a b a", "a", "c", all: true).1 == "2 remplacements")
    }

    static let widget = """
    class A {
      Widget build() {
        return IconButton(
          icon: const Icon(Icons.send),
          onPressed: onSend,
        );
      }
    }

    """

    @Test("seule l'indentation diffère : appliqué avec celle du fichier")
    func reindent() {
        let (out, note) = applyEdit(
            Self.widget,
            "return IconButton(\n  icon: const Icon(Icons.send),",
            "return IconButton(\n  tooltip: 'Envoyer le message',\n  icon: const Icon(Icons.send),"
        )
        #expect(note.contains("indentation"))
        #expect(out?.contains("    return IconButton(\n      tooltip: 'Envoyer le message',\n      icon: const Icon(Icons.send),\n      onPressed: onSend,") == true)
        #expect(out?.hasPrefix("class A {\n  Widget build() {\n") == true)
        #expect(out?.hasSuffix("  }\n}\n") == true)
        // Jamais appliqué au hasard si les lignes reviennent deux fois.
        #expect(applyEdit("  a();\n  b();\n\n    a();\n    b();\n", "a();\nb();", "c();").0 == nil)
    }

    @Test("passage introuvable : le plus proche est montré, avec ses numéros")
    func nearest() {
        let (out, why) = applyEdit(Self.widget, "IconButton(\n  tooltip: 'Envoyer',\n  icon: const Icon(Icons.send),", "x")
        #expect(out == nil)
        #expect(why.contains("passage introuvable"))
        #expect(why.contains("Le passage le plus proche"))
        #expect(why.contains("4:       icon: const Icon(Icons.send),"))
        #expect(nearestPassage(Self.widget, "fn main() { println!(\"x\"); }") == nil)
        #expect(!applyEdit(Self.widget, "zzz qqq", "x").1.contains("le plus proche"))
    }

    static let routes = """
    fn app() -> App {
        let mut app = App::new();
        app.get("/faq", faq);
        app.get("/mentions-legales", mentions);
        app.get("/confidentialite", confidentialite);
        app
    }

    """

    @Test("old coupé au milieu d'un mot : ajout après la ligne entière, ou refus")
    func cutWord() {
        let (out, note) = applyEdit(
            Self.routes,
            "    app.get(\"/mentions-legales\", men",
            "    app.get(\"/mentions-legales\", men\n    app.get(\"/sante\", sante);"
        )
        #expect(out?.contains("    app.get(\"/mentions-legales\", mentions);\n    app.get(\"/sante\", sante);\n    app.get(\"/confidentialite\", confidentialite);") == true)
        #expect(out?.contains("sante);tions") == false)
        #expect(note.contains("après la ligne entière"))

        let (o2, why) = applyEdit(Self.routes, "app.get(\"/mentions-legales\", men", "app.get(\"/mentions\", page")
        #expect(o2 == nil)
        #expect(why.contains("au milieu d'un mot (« men|tions »)"))
        #expect(why.contains("    app.get(\"/mentions-legales\", mentions);"))

        let (o3, why3) = applyEdit(Self.routes, "tions-legales\", mentions);", "\"/sante\", sante);")
        #expect(o3 == nil)
        #expect(why3.contains("commence au milieu d'un mot"))

        // Les remplacements normaux ne changent pas.
        #expect(applyEdit(Self.routes, "    app.get(\"/faq\", faq);", "    app.get(\"/faq\", faq);\n    app.get(\"/sante\", sante);").0?
            .contains("faq);\n    app.get(\"/sante\", sante);\n    app.get(\"/mentions") == true)
        #expect(applyEdit("let a = 1;", "a", "b").1 == "1 remplacement")
        #expect(applyEdit("foo(bar)", "foo(", "baz(").0 == "baz(bar)")
        #expect(applyEdit("let total_x = 1;", "let total", "var total").0 == "var total_x = 1;")
        #expect(applyEdit("xcount", "count", "count").0 == "xcount")
    }

    static let diffDart = """
    class DiffResult {
      int get added => 0;
    }

    /// Compare deux textes ligne à ligne (plus longue sous-suite commune, après
    /// avoir retiré le début et la fin identiques).
    DiffResult lineDiff(String? before, String? after) {
      return const DiffResult();
    }

    """

    static let newFn = """
    /// Le nombre de lignes ajoutées et supprimées.
    int countChangedLines(String before, String after) {
      final r = lineDiff(before, after);
      return r.added + r.removed;
    }


    """

    @Test("une fonction ajoutée avant une autre ne lui vole plus sa doc")
    func docComment() throws {
        let old = "DiffResult lineDiff(String? before, String? after) {"
        let (out, note) = applyEdit(Self.diffDart, old, Self.newFn + old)
        let o = try #require(out)
        #expect(note.contains("au-dessus du commentaire"))
        #expect(o.contains("identiques).\nDiffResult lineDiff(String? before, String? after) {"))
        #expect(o.indexOf("int countChangedLines") < o.indexOf("/// Compare deux textes"))
        #expect(o.contains(Self.newFn + "/// Compare deux textes"))
        #expect(o.replaceFirst(Self.newFn, "") == Self.diffDart)
    }

    @Test("annotations et attributs restent avec leur déclaration")
    func annotations() {
        let dart = "class A {\n  @override\n  String toString() => \"a\";\n}\n"
        #expect(applyEdit(dart, "  String toString() => \"a\";", "  int get n => 1;\n\n  String toString() => \"a\";").0
            == "class A {\n  int get n => 1;\n\n  @override\n  String toString() => \"a\";\n}\n")
        let rust = "/// Santé.\n#[get(\"/sante\")]\nasync fn sante() {}\n"
        #expect(applyEdit(rust, "async fn sante() {}", "async fn version() {}\n\nasync fn sante() {}").0
            == "async fn version() {}\n\n/// Santé.\n#[get(\"/sante\")]\nasync fn sante() {}\n")
        let js = "/**\n * Somme.\n */\nfunction add(a, b) {}\n"
        #expect(applyEdit(js, "function add(a, b) {}", "function sub(a, b) {}\n\nfunction add(a, b) {}").0
            == "function sub(a, b) {}\n\n/**\n * Somme.\n */\nfunction add(a, b) {}\n")
    }

    @Test("rien ne bouge sans commentaire au-dessus, ni pour un autre remplacement")
    func noMove() {
        let (p, note) = applyEdit("int a() => 1;\n\nint b() => 2;\n", "int b() => 2;", "int c() => 3;\nint b() => 2;")
        #expect(p == "int a() => 1;\n\nint c() => 3;\nint b() => 2;\n")
        #expect(note == "1 remplacement")
        #expect(applyEdit(Self.diffDart, "DiffResult lineDiff(String? before, String? after) {", "DiffResult lineDiff(String before, String after) {").0?
            .contains("identiques).\nDiffResult lineDiff(String before,") == true)
        #expect(applyEdit("/// Doc.\nfinal x = 1;\n", "final x = 1;", "const y = 2; final x = 1;").0 == "/// Doc.\nconst y = 2; final x = 1;\n")
        #expect(applyEdit(Self.diffDart, "/// Compare deux textes", "int z() => 0;\n\n/// Compare deux textes").0?
            .contains("int z() => 0;\n\n/// Compare deux textes") == true)
        #expect(applyEdit("# Titre\nPremier paragraphe.\n", "Premier paragraphe.", "Introduction.\n\nPremier paragraphe.").0
            == "# Titre\nIntroduction.\n\nPremier paragraphe.\n")
    }

    @Test("fins de ligne CRLF : remplacées comme Dart")
    func crlf() {
        #expect(applyEdit("a\r\nb\r\n", "a\nb", "c").0 == "c\n")
        #expect("a\r\nb".dsplit("\n") == ["a\r", "b"])
    }

    // MARK: - Ajouts à la fin (write_file « at_end »)

    static let notes = (1...300).map { "- Point numéro \($0)" }.joined(separator: "\n")

    @MainActor
    func notesRun(_ llm: ScriptLLM) -> AgentRun {
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["site/notes.md": Self.notes + "\n"]), task: "Ajoute un lien à la fin des notes", checks: false)
        run.specs.append("déjà compris")
        return run
    }

    @Test("les façons de demander un ajout à la fin")
    func appendModes() {
        #expect(AgentRun.appendMode(["at_end": true]))
        #expect(AgentRun.appendMode(["append": "true"]))
        #expect(AgentRun.appendMode(["mode": "append"]))
        #expect(!AgentRun.appendMode(["path": "a.md"]))
        #expect(!AgentRun.appendMode(["mode": "overwrite"]))
    }

    @Test("write_file « at_end » sans contenu : seul l'ajout est demandé, puis ajouté")
    @MainActor
    func appendPending() async {
        let llm = ScriptLLM([
            "```json\n{\"actions\":[{\"tool\":\"repo_browser.write_file\",\"args\":{\"path\":\"site/notes.md\",\"at_end\":true}}]}\n```",
            "```markdown\n[Retour en haut](#)\n```",
        ])
        let run = notesRun(llm)
        await run.run()
        #expect(run.draft("site/notes.md") == Self.notes + "\n[Retour en haut](#)\n")
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("texte à AJOUTER"))
        #expect(!second.contains("contenu COMPLET"))
        #expect(llm.messages(2).last?["content"]?.contains("texte ajouté à la fin") == true)
    }

    @Test("write_file « append » avec son contenu : ajouté une seule fois")
    @MainActor
    func appendOnce() async {
        let call = "```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"site/notes.md\",\"mode\":\"append\",\"content\":\"[Retour en haut](#)\"}}\n```"
        let run = notesRun(ScriptLLM([call, call]))
        await run.run()
        #expect(run.draft("site/notes.md") == Self.notes + "\n[Retour en haut](#)\n")
        #expect(run.draft("site/notes.md")?.components(separatedBy: "Retour en haut").count == 2)
    }

    @Test("write_file sans contenu sur un long fichier : edit_file est proposé")
    @MainActor
    func pendingLong() async {
        let llm = ScriptLLM(["```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"site/notes.md\"}}\n```"])
        let run = notesRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("utilise plutôt edit_file"))
        #expect(second.contains("\"at_end\": true"))
    }
}
