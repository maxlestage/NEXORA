import Foundation
import Testing
@testable import NexoraKit

func act(_ tool: String, _ args: [String: Any], _ content: String? = nil) -> String {
    act(["tool": tool, "args": args]) + (content.map { "\n```\n\($0)\n```" } ?? "")
}

/// Le langage NEXORA : traduction des demandes, suppositions marquées, chemins de
/// l'utilisateur gardés, traductions coupées, où vont les tests.
@Suite("Agent : langage NEXORA")
@MainActor
struct AgentSpecTests {
    static let spec1 = "OBJECTIF : aucune page du site ne défile horizontalement sur mobile\n"
        + "DEMANDES :\n1. Trouver les éléments plus larges que l'écran et les corriger\n"
        + "CONTRAINTES :\n- ne rien cacher du contenu\n"
        + "CRITÈRES DE RÉUSSITE :\n- la largeur du document ne dépasse jamais celle de l'écran\n- un test le vérifie\n"
        + "INTERPRÉTATIONS :\n- « le site » = toutes les pages"

    static let spec2 = "OBJECTIF : le titre est en bleu\nDEMANDES :\n1. Passer h1 en bleu\n"
        + "CONTRAINTES :\n- aucune\nCRITÈRES DE RÉUSSITE :\n- h1 est bleu\nINTERPRÉTATIONS :\n- aucune"

    let emptyRepo = Routes { _ in (200, #"{"tree":[]}"#) }

    @Test("chaque demande est traduite, affichée et donnée à l'agent à chaque étape")
    func translated() async throws {
        let llm = ScriptLLM([
            Self.spec1,
            act("write_file", ["path": "a.css"], "html { overflow-x: clip; }"),
            act("finish", ["summary": "Fait ✅"]),
            Self.spec2,
            act("write_file", ["path": "b.css"], "h1 { color: blue; }"),
            act("finish", ["summary": "Bleu ✅"]),
        ])
        let run = makeRun(llm, hub: emptyRepo, task: "je veux aucun défilement horizontal", checks: false, compile: true)
        await run.run()
        #expect(llm.prompt(0).contains("LANGAGE NEXORA"))
        #expect(llm.prompt(0).contains("je veux aucun défilement horizontal"))
        #expect(run.steps.first?.kind == .goal)
        #expect(run.steps.first?.text.hasPrefix("OBJECTIF : aucune page") == true)
        #expect(llm.prompt(1).contains("En langage NEXORA"))
        #expect(llm.prompt(1).contains("ne rien cacher du contenu"))
        #expect(llm.prompt(2).contains("Critères de réussite à remplir"))
        #expect(llm.prompt(2).contains("un test le vérifie"))
        #expect(run.specs == [Self.spec1])

        await run.run(followUp: "mets aussi le titre en bleu")
        #expect(llm.prompt(3).contains("Demandes précédentes"))
        #expect(run.specs == [Self.spec1, Self.spec2])
        #expect(run.summary == "Bleu ✅")
        #expect(run.steps.filter { $0.kind == .goal }.count == 2)
        #expect(run.toJSON()["specs"] as? [String] == [Self.spec1, Self.spec2])
    }

    @Test("le traducteur voit les vrais fichiers du dépôt : il n'invente ni chemin ni code")
    func translatorSeesFiles() async throws {
        let llm = ScriptLLM([Self.spec2] + Array(repeating: act("finish", ["summary": "ok"]), count: 4))
        let trees = Locked(0)
        let hub = Routes { c in
            if c.path.contains("/git/trees/") { trees.update { $0 += 1 } }
            return (200, treeJSON(["app/lib/utils/format.dart", "app/test/format_test.dart"]))
        }
        let run = makeRun(llm, hub: hub, task: "ajoute une fonction qui formate une durée", checks: false, compile: true)
        await run.run()
        let ask = llm.messages(0).map { $0["content"] ?? "" }.joined(separator: "\n")
        #expect(ask.contains("Fichiers du dépôt"))
        #expect(ask.contains("app/lib/utils/format.dart"))
        let sys = llm.prompt(0)
        #expect(sys.contains("sans inventer de chemin"))
        #expect(sys.contains("N'écris pas de code"))
        #expect(sys.contains("ne nomme une fonction"))
        #expect(sys.contains("la fonction qui compare les versions"))
        #expect(sys.contains("ne le choisis pas"))
        #expect(llm.prompt(1).contains("ce sont ses mots qui comptent"))
        #expect(llm.prompt(1).contains("n'est pas celui que"))
        #expect(trees.get() == 1)
        #expect(llm.prompt(1).contains("app/test/format_test.dart"))
    }

    @Test("traduction ratée : l'agent travaille avec la demande brute")
    func failed() async {
        let run = makeRun(ScriptLLM(["Désolé, je ne sais pas.", act("finish", ["summary": "ok"]), act("finish", ["summary": "ok"])]),
                          hub: emptyRepo, task: "dis bonjour", checks: false, compile: true)
        await run.run()
        #expect(run.specs == [""])
        #expect(!run.steps.contains { $0.kind == .goal })
        #expect(run.summary == "ok")
    }

    // MARK: - Suppositions

    static let guessed = "OBJECTIF : compter les versions publiées\n"
        + "DEMANDES :\n"
        + "1. Dans le fichier **site/src/export.rs**, ajouter une fonction qui compte les titres de version de site/src/nouveautes.md\n"
        + "2. Ajouter un test unitaire Rust\n"
        + "CONTRAINTES :\n"
        + "- Le fichier modifié doit être exactement **site/src/export.rs**.\n"
        + "CRITÈRES DE RÉUSSITE :\n"
        + "- cargo test passe\n"
        + "INTERPRÉTATIONS :\n"
        + "- aucune"
    static let files = ["site/src/contenu.rs", "site/src/export.rs", "site/src/nouveautes.md"]

    @Test("un fichier deviné ne devient plus une contrainte stricte")
    func guesses() {
        let out = AgentRun.markGuesses(
            Self.guessed,
            "Dans le site (dossier site/), ajoute dans le fichier qui gère les nouveautés une fonction qui compte les versions publiées, avec un test.",
            Self.files
        )
        let contraintes = out.sub(out.indexOf("CONTRAINTES"), out.indexOf("CRITÈRES"))
        #expect(!contraintes.contains("export.rs"))
        #expect(contraintes.contains("- aucune"))
        let interp = out.sub(out.indexOf("INTERPRÉTATIONS"))
        #expect(interp.contains("Supposé (à vérifier dans le dépôt)"))
        #expect(interp.contains("site/src/export.rs, site/src/nouveautes.md"))
        #expect(interp.contains("modifie le bon fichier"))
        #expect(!interp.contains("- aucune"))
        #expect(out.contains("1. Dans le fichier **site/src/export.rs**"))

        #expect(AgentRun.markGuesses(Self.guessed, "Ajoute dans export.rs une fonction qui compte les versions de site/src/nouveautes.md", Self.files) == Self.guessed)
        #expect(AgentRun.markGuesses(Self.spec2, "Mets le titre en bleu", Self.files) == Self.spec2)
        let noInterp = "OBJECTIF : corriger le menu\nDEMANDES :\n1. Corriger app/lib/menu.dart\nCONTRAINTES :\n- ne rien casser"
        let o = AgentRun.markGuesses(noInterp, "Corrige le menu")
        #expect(o.contains("CONTRAINTES :\n- ne rien casser"))
        #expect(o.hasSuffix("modifie le bon fichier."))
        #expect(o.contains("INTERPRÉTATIONS :\n- Fichiers supposés"))
        #expect(o.contains("app/lib/menu.dart"))
        let domain = "OBJECTIF : lien\nDEMANDES :\n1. Ajouter un lien vers pollinations.ai\nCONTRAINTES :\n- aucune"
        #expect(AgentRun.markGuesses(domain, "Ajoute un lien", Self.files) == domain)
    }

    // MARK: - Chemins de l'utilisateur

    static let tree = ["README.md", "app/lib/main.dart", "app/test/app_test.dart", "site/src/main.rs"]

    @Test("un dossier écrit par l'utilisateur et perdu revient dans les contraintes")
    func userPaths() {
        let spec = "OBJECTIF : Ajouter slugify dans le fichier utilitaire.\n"
            + "DEMANDES :\n1. Ajouter slugify dans le fichier utilitaire.\n"
            + "2. Créer app/test/slugify_test.dart.\n"
            + "CONTRAINTES :\n- aucune\n"
            + "CRITÈRES DE RÉUSSITE :\n- Les tests passent."
        let out = AgentRun.keepUserPaths(spec, "Ajoute dans app/lib/utils/ une fonction slugify, avec ses tests dans app/test/.", Self.tree)
        #expect(out.contains("CONTRAINTES :\n- Emplacement écrit par l'utilisateur, à respecter tel quel : app/lib/utils/ (dossier à créer"))
        #expect(!out.contains("tel quel : app/test/"))
        #expect(!out.contains("- aucune"))
        #expect(out.contains("CRITÈRES DE RÉUSSITE :\n- Les tests passent."))

        let oneLine = "OBJECTIF : Une route.\nDEMANDES :\n1. Ajouter la route.\nCONTRAINTES : aucune\nCRITÈRES DE RÉUSSITE :\n- ok"
        let o2 = AgentRun.keepUserPaths(oneLine, "Ajoute une route dans site/src/routes.rs.", Self.tree)
        #expect(o2.contains("CONTRAINTES :\n- Emplacement écrit par l'utilisateur, à respecter tel quel : site/src/routes.rs\nCRITÈRES"))
        #expect(!o2.contains("routes.rs (dossier"))

        let o3 = AgentRun.keepUserPaths("OBJECTIF : x\nDEMANDES :\n1. y", "Range ça dans app/lib/outils", Self.tree)
        #expect(o3.hasSuffix("tel quel : app/lib/outils (dossier à créer s'il n'existe pas : le nouveau code va dedans)"))
        #expect(o3.contains("\nCONTRAINTES :\n"))

        let keep = "OBJECTIF : x\nDEMANDES :\n1. Modifier App/Lib/Main.dart\nCONTRAINTES :\n- aucune"
        #expect(AgentRun.keepUserPaths(keep, "Affiche la taille en Ko/Mo et/ou en octets, comme sur https://exemple.fr/doc/page.html, dans app/lib/main.dart.", Self.tree) == keep)
        #expect(AgentRun.keepUserPaths("", "dans app/lib/utils/", Self.tree) == "")
    }

    // MARK: - Traductions coupées

    static let cutSpec = "OBJECTIF : Ajouter une fonction publique countChangedLines dans app/lib/services/diff.dart et un test unitaire.\n\nDEMANDES :\n1. Dans"
    static let fullSpec = "OBJECTIF : Ajouter une fonction publique countChangedLines dans app/lib/services/diff.dart et un test unitaire.\n"
        + "DEMANDES :\n1. Ajouter countChangedLines(String before, String after) dans app/lib/services/diff.dart\n2. Écrire son test unitaire\n"
        + "CONTRAINTES :\n- garder la signature demandée\nCRITÈRES DE RÉUSSITE :\n- le test passe\nINTERPRÉTATIONS :\n- aucune"
    static let cutTask = "Dans l'app, ajoute dans app/lib/services/diff.dart une fonction publique countChangedLines(String before, String after), avec un test."

    @Test("une traduction arrêtée au premier mot des demandes est incomplète")
    func complete() {
        #expect(!AgentRun.specComplete(Self.cutSpec))
        #expect(!AgentRun.specComplete(Self.cutSpec, cut: true))
        #expect(AgentRun.specComplete(Self.fullSpec))
        #expect(AgentRun.specComplete(Self.fullSpec, cut: true))
        #expect(AgentRun.specComplete("**OBJECTIF**\nAjouter la fonction demandée\n\n**DEMANDES**\n| # | Demande |\n| 1 | Implémenter la fonction |"))
        #expect(!AgentRun.specComplete("OBJECTIF : ajouter la fonction demandée"))
        #expect(!AgentRun.specComplete("OBJECTIF : ajouter la fonction demandée\nDEMANDES :\n1. Ajouter la fonction\n2. Écrire le te", cut: true))
        #expect(AgentRun.specComplete("OBJECTIF : ajouter la fonction demandée\nDEMANDES :\n1. Ajouter la fonction et son test"))
    }

    func cutRun(_ replies: [Reply]) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies: replies)
        llm.whenEmpty = act("finish", ["summary": "Fait ✅"])
        return (makeRun(llm, hub: emptyRepo, repo: "NEXORA", branch: "master", task: Self.cutTask, checks: false, compile: true), llm)
    }

    @Test("une traduction coupée en route est redemandée, et la bonne sert")
    func cutRetried() async {
        let (run, llm) = cutRun([.cut(Self.cutSpec), .text(Self.fullSpec), .text(act("finish", ["summary": "Fait ✅"]))])
        await run.run()
        #expect(llm.prompt(1).contains("LANGAGE NEXORA"))
        #expect(run.specs.count == 1)
        #expect(run.specs.first?.hasPrefix(Self.fullSpec) == true)
        let goals = run.steps.filter { $0.kind == .goal }
        #expect(goals.count == 1)
        #expect(goals.first?.text.contains("2. Écrire son test unitaire") == true)
        #expect(goals.first?.text.contains("1. Dans\n") == false)
        #expect(llm.prompt(2).contains("2. Écrire son test unitaire"))
        #expect(run.summary == "Fait ✅")

        // Tronquée sans signal de coupure : redemandée aussi.
        let (run2, _) = cutRun([.text(Self.cutSpec), .text(Self.fullSpec), .text(act("finish", ["summary": "Fait ✅"]))])
        await run2.run()
        #expect(run2.specs.first?.hasPrefix(Self.fullSpec) == true)
    }

    @Test("deux traductions coupées : l'agent travaille avec la demande brute")
    func twoCuts() async {
        let (run, llm) = cutRun([.cut(Self.cutSpec), .cut(Self.cutSpec), .text(act("finish", ["summary": "Fait ✅"]))])
        await run.run()
        #expect(run.specs == [""])
        #expect(!run.steps.contains { $0.kind == .goal })
        #expect(llm.prompt(2).contains("countChangedLines(String before, String after)"))
        #expect(!llm.prompt(2).contains("1. Dans\n"))
        #expect(run.summary == "Fait ✅")
    }

    // MARK: - Où vont les tests

    static let nexora = [
        ".github/workflows/ci.yml", "app/pubspec.yaml", "app/lib/main.dart", "app/lib/ui/home.dart",
        "app/test/app_test.dart", "site/Cargo.toml", "site/src/lib.rs", "site/src/main.rs", "site/tests/iles.rs",
    ]

    @Test("où vont les tests de chaque projet")
    func layout() {
        let l = AgentRun.testLayout(Self.nexora)
        #expect(l.contains("app/ (Dart/Flutter) : app/test/<nom>_test.dart"))
        #expect(l.contains("flutter_test"))
        #expect(!l.contains("dossier à créer"))
        #expect(l.contains("site/ (Rust) : site/tests/<nom>.rs"))
        #expect(l.contains("Ce qui est défini dans site/src/main.rs (routes, app(), fonctions du programme) se teste UNIQUEMENT dans son module « #[cfg(test)] mod tests »"))

        let bin = AgentRun.testLayout(["Cargo.toml", "src/main.rs", "README.md"])
        #expect(bin.hasPrefix("- la racine (Rust, programme sans bibliothèque)"))
        #expect(bin.contains("src/main.rs"))
        #expect(bin.contains("Jamais dans tests/"))
        let lib = AgentRun.testLayout(["Cargo.toml", "src/lib.rs"])
        #expect(lib.contains("tests/<nom>.rs"))
        #expect(!lib.contains("main.rs"))

        let many = AgentRun.testLayout(["web/package.json", "web/__tests__/a.test.js", "api/pyproject.toml", "api/setup.py", "cli/go.mod", "pkg/pubspec.yaml", "pkg/lib/pkg.dart"])
        #expect(many.contains("web/ (JavaScript/TypeScript) : web/__tests__/"))
        #expect(many.contains("api/ (Python) : api/tests/test_<nom>.py"))
        #expect(many.components(separatedBy: "(Python)").count == 2)
        #expect(many.contains("cli/ (Go) : <nom>_test.go"))
        #expect(many.contains("pkg/test/<nom>_test.dart (dossier à créer)"))
        #expect(many.contains("package:test"))
        #expect(AgentRun.testLayout(["node_modules/x/package.json"]).isEmpty)
        #expect(AgentRun.testLayout(["README.md", "index.html"]).isEmpty)
    }

    @Test("la traduction reçoit le repère des projets qu'elle concerne")
    func withLayout() {
        let layout = AgentRun.testLayout(Self.nexora)
        let spec = "OBJECTIF : ajouter une route /sante au site.\nDEMANDES :\n1. Modifier site/src/main.rs.\n2. Créer site/tests/sante_test.rs."
        let out = AgentRun.withTestLayout(spec, layout)
        #expect(out.hasPrefix(spec))
        #expect(out.contains("OÙ VONT LES TESTS"))
        #expect(out.contains("prime sur tout autre chemin de test"))
        #expect(out.contains("UNIQUEMENT dans son module « #[cfg(test)]"))
        #expect(!out.contains("Dart/Flutter"))
        #expect(AgentRun.withTestLayout("", layout).isEmpty)
        #expect(AgentRun.withTestLayout(spec, "") == spec)
        let one = AgentRun.testLayout(["Cargo.toml", "src/main.rs"])
        #expect(AgentRun.withTestLayout("OBJECTIF : une route.", one).contains("Jamais dans tests/"))
    }

    @Test("le repère est donné à l'agent dès le premier message")
    func layoutFirstMessage() async {
        let llm = ScriptLLM()
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(Dictionary(uniqueKeysWithValues: Self.nexora.map { ($0, "x") })), owner: "o", repo: "r",
                          task: "Ajoute une route /sante au site, avec son test.")
        await run.run()
        let first = llm.messages(0).map { $0["content"] ?? "" }.joined(separator: "\n")
        #expect(first.contains("OÙ ÉCRIRE LES TESTS (inutile de le chercher)"))
        #expect(first.contains("son module « #[cfg(test)] mod tests »"))
    }

    // MARK: - Tests Rust mal placés

    static let site = ["site/Cargo.toml", "site/src/lib.rs", "site/src/main.rs", "site/tests/iles.rs"]
    static let rustSpec = "OBJECTIF : Ajouter une route GET /sante qui renvoie « ok ».\n\n"
        + "DEMANDES :\n"
        + "1. Dans site/src/main.rs, ajouter une route GET /sante.\n"
        + "2. Créer un fichier de test Rust (site/tests/sante_test.rs) qui vérifie la réponse.\n\n"
        + "CRITÈRES DE RÉUSSITE :\n"
        + "- Le test site/tests/sante_test.rs passe sans erreur."

    @Test("un test de route du programme ne va plus dans tests/")
    func rustPaths() {
        let out = AgentRun.fixRustTestPaths(Self.rustSpec, Self.site)
        #expect(!out.contains("site/tests/sante_test.rs"))
        #expect(out.contains("site/src/main.rs (dans son module « #[cfg(test)] mod tests », pas dans site/tests/ qui ne voit pas le programme)"))
        #expect(out.contains("1. Dans site/src/main.rs, ajouter une route GET"))
        let bin = AgentRun.fixRustTestPaths("DEMANDES :\n1. Créer tests/outil.rs pour tester parse().", ["Cargo.toml", "src/main.rs"])
        #expect(bin.contains("src/main.rs (dans son module"))
        #expect(!bin.contains("tests/outil.rs"))
        for keep in [
            "DEMANDES :\n1. Compléter site/tests/iles.rs.",
            "DEMANDES :\n1. Modifier site/src/lib.rs.\n2. Créer site/tests/scene.rs.",
            "DEMANDES :\n1. Créer site/tests/contenu.rs.",
        ] {
            #expect(AgentRun.fixRustTestPaths(keep, Self.site) == keep)
        }
        #expect(AgentRun.fixRustTestPaths("DEMANDES :\n1. Créer tests/a.rs.", ["README.md"]) == "DEMANDES :\n1. Créer tests/a.rs.")
    }

    @Test("la demande donnée à l'agent ne cite plus le mauvais chemin")
    func rustPathInSession() async {
        let llm = ScriptLLM([Self.rustSpec])
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(Dictionary(uniqueKeysWithValues: Self.site.map { ($0, "x") })), owner: "o", repo: "r",
                          task: "Ajoute une route GET /sante au site, avec un test Rust.", compile: true)
        await run.run()
        #expect(llm.count >= 2)
        let agent = llm.messages(1).map { $0["content"] ?? "" }.joined(separator: "\n") + llm.prompt(1)
        #expect(agent.contains("OBJECTIF : Ajouter une route GET /sante"))
        #expect(!agent.contains("site/tests/sante_test.rs"))
        #expect(agent.contains("dans son module « #[cfg(test)] mod tests »"))
    }
}
