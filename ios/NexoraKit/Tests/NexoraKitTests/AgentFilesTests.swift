import Foundation
import Testing
@testable import NexoraKit

/// Les fichiers : chemins presque justes, lectures par plages, plan d'un long
/// fichier, recherche (expressions régulières, mots entiers).
@Suite("Agent : fichiers et recherche")
@MainActor
struct AgentFilesTests {
    static let tree = [
        ".github/workflows/ci.yml", ".github/workflows/app.yml", "app/lib/main.dart",
        "app/test/app_test.dart", "site/src/nouveautes.md", "README.md",
    ]

    func fix(_ p: String, creating: Bool = false, mounts: [String] = []) -> String? {
        AgentRun.fixPath(p, Self.tree, repoName: "NEXORA", mounts: mounts, creating: creating)
    }

    @Test("chemins presque justes : point oublié, « ./ », casse, nom du dépôt")
    func fixPath() {
        #expect(fix("github/workflows/ci.yml") == ".github/workflows/ci.yml")
        #expect(fix("github/workflows") == ".github/workflows")
        #expect(fix("github/workflows/tests.yml", creating: true) == ".github/workflows/tests.yml")
        #expect(fix("./app/lib/main.dart") == "app/lib/main.dart")
        #expect(fix("readme.md") == "README.md")
        #expect(fix("NEXORA/site/src/nouveautes.md") == "site/src/nouveautes.md")
    }

    @Test("un chemin juste ou un vrai nouveau fichier n'est pas touché")
    func fixPathKeeps() {
        #expect(fix("app/lib/main.dart") == nil)
        #expect(fix(".github/workflows/ci.yml") == nil)
        #expect(fix("app/test/new_test.dart", creating: true) == nil)
        #expect(fix("docs/guide.md", creating: true) == nil)
        #expect(fix("lib/inconnu.dart") == nil)
        #expect(fix("notes.md", creating: true) == nil)
    }

    @Test("dossier de projet ajouté ou oublié ; rien de deviné sans certitude")
    func fixPathDirs() {
        #expect(fix("app/.github/workflows/ci.yml") == ".github/workflows/ci.yml")
        #expect(fix("site/README.md") == "README.md")
        #expect(fix("lib/main.dart") == "app/lib/main.dart")
        #expect(fix("src/nouveautes.md") == "site/src/nouveautes.md")
        #expect(fix("app/README.md", creating: true) == nil)
        #expect(AgentRun.fixPath("lib/a.dart", ["app/lib/a.dart", "pkg/lib/a.dart"]) == nil)
        #expect(fix("docs/README.md") == nil)
        #expect(AgentRun.fixPath("lib/main.dart", Self.tree, moveDirs: false) == nil)
        #expect(AgentRun.fixPath("src/lib.rs", ["paquets/src/lib.rs", "nexora/app/lib/main.dart"], mounts: ["paquets", "nexora"]) == "paquets/src/lib.rs")
        #expect(AgentRun.fixPath("README.md", ["a/README.md", "b/README.md"], mounts: ["a", "b"]) == nil)
    }

    @Test("l'agent lit le fichier du premier coup, et apprend le bon chemin")
    func fixPathInSession() async {
        let llm = ScriptLLM([
            act(["tool": "read_file", "args": ["path": "github/workflows/ci.yml"]]),
            act(["tool": "finish", "args": ["summary": "Lu"]]),
        ])
        let run = makeRun(llm, hub: repoHub([".github/workflows/ci.yml": "name: CI\n"]), task: "Lis la CI", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(run.summary == "Lu")
        let seen = llm.prompt(1)
        #expect(seen.contains("name: CI"))
        #expect(seen.contains("c'est « .github/workflows/ci.yml »"))
        #expect(!seen.contains("Fichier introuvable"))
    }

    // MARK: - Plan d'un long fichier

    static func bigRust() -> String {
        var b = "use paquets::prelude::*;\n\n"
        for i in 0..<700 { b += "// remplissage \(i) : texte de la page, OpenRouter, Groq…\n" }
        b += [
            "async fn accueil(_req: Request) -> Page {", "    Page::new(\"Accueil\")", "}", "",
            "fn app() -> App {", "    let mut app = App::new();", "    app.get(\"/\", accueil);",
            "    if let Some(x) = Some(1) {", "        app.health(\"/health\");", "    }", "    app", "}", "",
            "#[cfg(test)]", "mod tests {", "    use super::*;", "    #[tokio::test]",
            "    async fn chaque_page_repond() {", "        let client = app().test().await;",
            "        assert_eq!(client.get(\"/\").await.status(), 200);", "    }", "}",
        ].map { $0 + "\n" }.joined()
        return b
    }

    @Test("long fichier lu sans plage : le plan du reste, avec les lignes")
    func outlineRest() {
        let text = Self.bigRust()
        let out = AgentRun.readRange("site/src/main.rs", text, nil, nil)
        #expect(out.contains("Lignes 1 à 600 sur"))
        #expect(out.contains("Plan du reste du fichier"))
        let lines = text.dsplit("\n")
        func lineOf(_ s: String) -> Int { (lines.firstIndex { $0.hasPrefix(s) } ?? -1) + 1 }
        #expect(out.contains("\(lineOf("fn app()")): fn app() -> App {"))
        #expect(out.contains("\(lineOf("async fn accueil")): async fn accueil"))
        #expect(out.contains("\(lineOf("#[cfg(test)]")): #[cfg(test)]"))
        #expect(out.contains("mod tests {"))
        #expect(out.contains("async fn chaque_page_repond()"))
        let plan = out.sub(out.indexOf("Plan du reste"))
        for noise in ["remplissage", "app.get(", "if let", "assert_eq!", "#[tokio::test]"] {
            #expect(!plan.contains(noise), "\(noise)")
        }
        // Plage demandée ou fichier court : rien ne change.
        #expect(!AgentRun.readRange("site/src/main.rs", text, 690, 720).contains("Plan du reste"))
        let short = "fn main() {\n    println!(\"ok\");\n}\n"
        #expect(AgentRun.readRange("src/main.rs", short, nil, nil) == short)
    }

    @Test("plan d'un fichier Dart, Python ou JavaScript")
    func outlines() {
        let dart = "import 'x.dart';\nclass Session extends ChangeNotifier {\n  Session(this.id);\n  final String id;\n"
            + "  Future<void> run({String? followUp}) async {\n    if (x) {\n      await save();\n    } else if (y) {\n    }\n"
            + "    return;\n  }\n  void _finish(\n    Conversation c, {\n    required void Function() flush,\n  }) {}\n}\n"
            + "void main() {\n  test('ça marche', () {});\n}\n"
        let plan = AgentRun.outline(dart)
        #expect(plan.contains("2: class Session extends ChangeNotifier {"))
        #expect(plan.contains("5:   Future<void> run({String? followUp}) async {"))
        #expect(plan.contains("12:   void _finish("))
        #expect(plan.contains("17: void main() {"))
        #expect(plan.contains("18:   test('ça marche'"))
        for noise in ["else if", "await save", "required", "final String id"] { #expect(!plan.contains(noise), "\(noise)") }
        #expect(AgentRun.outline("import os\n\nclass Api:\n    def get(self):\n        return 1\n") == "3: class Api:\n4:     def get(self):")
        let js = "export default function App() {\n  const [a, setA] = useState(0);\n  return a;\n}\nexport async function load(url) {}\n"
        #expect(AgentRun.outline(js) == "1: export default function App() {\n5: export async function load(url) {}")
    }

    @Test("beaucoup de définitions : premier niveau d'abord, et le nombre laissé")
    func outlineMax() {
        var b = ""
        for i in 0..<100 { b += "class C\(i) {\n  void m\(i)() {}\n}\n" }
        let entries = AgentRun.outline(b, max: 80).dsplit("\n")
        #expect(entries.count == 81)
        #expect(entries.prefix(80).allSatisfy { $0.contains(": class C") })
        #expect(entries.last?.contains("120 autres définitions") == true)
    }

    // MARK: - Plages de lignes

    @Test("les lignes à lire, quel que soit le nom des arguments")
    func spans() {
        func eq(_ a: (Int?, Int?, Int?), _ b: (Int?, Int?, Int?)) -> Bool { a.0 == b.0 && a.1 == b.1 && a.2 == b.2 }
        #expect(eq(AgentRun.readSpan(["start": 10, "end": 20]), (10, 20, nil)))
        #expect(eq(AgentRun.readSpan(["offset": 10, "limit": 5]), (10, 15, nil)))
        #expect(eq(AgentRun.readSpan(["line": 50]), (nil, nil, 50)))
        #expect(eq(AgentRun.readSpan([:]), (nil, nil, nil)))
        #expect(eq(AgentRun.readSpan(["line_start": 1800, "line_end": 1845]), (1800, 1845, nil)))
        #expect(eq(AgentRun.readSpan(["start_line": "12", "end_line": "30"]), (12, 30, nil)))
        #expect(eq(AgentRun.readSpan(["from": 5, "to": 9]), (5, 9, nil)))
        #expect(eq(AgentRun.readSpan(["lines": "10-20"]), (10, 20, nil)))
        #expect(eq(AgentRun.readSpan(["range": [10, 20]]), (10, 20, nil)))
        #expect(eq(AgentRun.readSpan(["line": 1, "end": 400]), (1, 400, nil)))
    }

    @Test("une lecture par line_start/line_end rend ces lignes, pas le début")
    func spanInSession() async {
        let file = (1...2000).map { "ligne numéro \($0)" }.joined(separator: "\n")
        let llm = ScriptLLM([
            act(["tool": "repo_browser.open_file", "args": ["path": "src/main.rs", "line_start": 1800, "line_end": 1805]]),
            act(["tool": "finish", "args": ["summary": "Lu"]]),
        ])
        let run = makeRun(llm, hub: repoHub(["src/main.rs": file]), task: "Lis la fin du fichier", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(run.summary == "Lu")
        let seen = llm.last(1)
        #expect(seen.contains("ligne numéro 1800"))
        #expect(seen.contains("ligne numéro 1805"))
        #expect(!seen.contains("ligne numéro 1806"))
        #expect(!seen.contains("ligne numéro 1\n"))
        #expect(seen.contains("Lignes 1800 à 1805 sur 2000"))
    }

    // MARK: - Recherche

    static let mainRs = """
    use paquets::prelude::*;

    async fn accueil(_req: Request) -> Page {
        page("/")
    }

    async fn robots(_req: Request) -> String {
        "User-agent: *".into()
    }

    fn app() -> App {
        let mut app = App::new();
        app.get("/", accueil);
        app.get("/robots.txt", robots);
        app
    }

    """

    func search(_ query: String, _ files: [String: String], task: String = "Trouve les pages") async throws -> String {
        let llm = ScriptLLM([
            act(["tool": "search_code", "args": ["query": query]]),
            act(["tool": "finish", "args": ["summary": "Cherché"]]),
        ])
        let run = makeRun(llm, hub: repoHub(files), repo: "nexora", task: task, checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(run.summary == "Cherché")
        return try #require(run.history.first { $0.content.hasPrefix("Résultat de search_code") }).content
    }

    @Test("expressions régulières reconnues ; texte simple gardé")
    func regexes() {
        for q in [#"async fn .* -> String"#, #"fn (accueil|robots)"#, #"^use "#, #"app\.get\("#, #"\bApp\b"#, #"(?i)robots"#, #"Page$"#] {
            #expect(AgentRun.isRegexQuery(q), "\(q)")
        }
        for q in ["app()", "#[tokio::test]", "send(\"", "mod tests", "-> String", "Response::new()"] {
            #expect(!AgentRun.isRegexQuery(q), "\(q)")
        }
        #expect(!AgentRun.isRegexQuery("fn (a|b"))
        #expect(!AgentRun.isRegexQuery("a || b"))
        #expect(!AgentRun.isRegexQuery(".*"))
    }

    @Test("une recherche en expression régulière trouve ce qu'elle décrit")
    func regexSearch() async throws {
        let files = ["site/src/main.rs": Self.mainRs]
        let r = try await search(#"async fn .* -> String"#, files)
        #expect(r.contains("expression régulière"))
        #expect(r.contains(">7: async fn robots(_req: Request) -> String {"))
        #expect(!r.contains("Aucune ligne"))
        #expect(!r.contains(">3: async fn accueil"))
        #expect(try await search(#"app\.get\("/(robots|inconnu)"#, files).contains(">14:     app.get(\"/robots.txt\", robots);"))
        let plain = try await search("app()", files)
        #expect(!plain.contains("expression régulière"))
        #expect(plain.contains(">11: fn app() -> App {"))
    }

    static let agentDart = """
    /// Un agent : un nom, une consigne système, des outils.
    class Agent {
      /// Outils autorisés en mode autonome (vide : tous).
      final List<String> tools = [];
    }

    """

    @Test("un mot entier, pas la fin d'un autre mot")
    func wholeWord() {
        #expect(!AgentRun.wholeWord("des outils", "utils"))
        #expect(!AgentRun.wholeWord("/// Outils autorisés", "utils"))
        #expect(AgentRun.wholeWord("import 'utils.dart';", "utils"))
        #expect(AgentRun.wholeWord("lib/utils/duree.dart", "utils"))
        #expect(AgentRun.wholeWord("my_utils()", "utils"))
        #expect(AgentRun.wholeWord("String formatDuree(d)", "duree"))
        #expect(AgentRun.wholeWord("outils puis utils", "utils"))
    }

    @Test("« utils » seulement dans « outils » : le nom n'existe pas ; vraies correspondances d'abord")
    func wholeWordSearch() async throws {
        let task = "Ajoute formatDuree dans lib/utils"
        let r = try await search("utils", ["app/lib/models/agent.dart": Self.agentDart], task: task)
        #expect(r.contains("Aucune ligne ne contient « utils » comme nom"))
        #expect(r.contains("« outils »"))
        #expect(r.contains("« Outils »"))
        #expect(r.contains("n'existe donc pas encore"))
        #expect(r.contains("crée-le"))
        #expect(!r.contains("agent.dart:1"))

        let r2 = try await search("utils", ["app/lib/models/agent.dart": Self.agentDart, "app/lib/main.dart": "import 'utils.dart';\nvoid main() {}\n"], task: task)
        #expect(r2.contains("1 ligne(s) contiennent « utils » (le mot lui-même ; "))
        #expect(r2.contains("import 'utils.dart';"))
        #expect(!r2.contains("des outils"))

        let r3 = try await search("agent", ["app/lib/models/agent.dart": Self.agentDart], task: task)
        #expect(r3.hasPrefix("Résultat de search_code"))
        #expect(r3.contains("ligne(s) contiennent « agent », avec le code"))
        #expect(!r3.contains("le mot lui-même"))
    }
}
