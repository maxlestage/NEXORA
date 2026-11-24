import Foundation
import Testing
@testable import NexoraKit

/// Essai réel (Flutter 2.2.84) : « ajoute une page /faq… » alors que la page existe
/// déjà. Le modèle trouvait la route, puis refaisait la même recherche ; les relances
/// lui affirmaient « ce que tu cherches N'EXISTE PAS » et « fais la première
/// modification », et la session s'arrêtait sans rien dire.
@Suite("Agent : demande déjà faite")
@MainActor
struct AgentExistingTests {
    nonisolated static let mainRs = """
    fn app() -> App {
        let mut app = App::new();
        app.get("/faq", faq);
        app
    }

    async fn faq(_req: Request) -> Page {
        page("/faq", "Questions fréquentes")
    }

    """

    func build(_ query: String) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM()
        llm.byModel = { _, _, last in
            // Une fois prévenu que la demande existe peut-être déjà, il le dit.
            if last.contains("EXISTE PEUT-ÊTRE DÉJÀ") {
                return .text(act(["tool": "finish", "args": ["summary": "La page /faq existe déjà (site/src/main.rs)."]]))
            }
            return .text(act(["tool": "search_code", "args": ["query": query, "path": "site/src/main.rs"]]))
        }
        let run = makeRun(llm, hub: repoHub(["site/src/main.rs": Self.mainRs]), task: "Ajoute une page /faq au site", checks: false)
        run.specs.append("déjà compris")
        return (run, llm)
    }

    func prompts(_ llm: ScriptLLM) -> [String] { (0..<llm.count).map { llm.last($0) } }

    @Test("foundSomething : une recherche avec des lignes, pas un échec")
    func found() {
        #expect(AgentRun.foundSomething("search_code", "Résultat de search_code :\n2 ligne(s) contiennent « faq » :"))
        #expect(AgentRun.foundSomething("search_code", "Résultat de search_code (faq) :\nRien dans a.rs. Dans tout le dépôt : b.rs:3"))
        #expect(!AgentRun.foundSomething("search_code", "Aucune ligne ne contient « faq » (1 fichiers parcourus)."))
        #expect(!AgentRun.foundSomething("find_in_file", "Résultat de find_in_file :\nAucune ligne ne contient « x » dans a.rs."))
        #expect(!AgentRun.foundSomething("find_in_file", "ERREUR : x"))
        #expect(!AgentRun.foundSomething("find_in_file", "Fichier introuvable : a.rs"))
        // Lire ou lister ne prouve pas que la demande est déjà faite.
        #expect(!AgentRun.foundSomething("read_file", "fn faq() {}"))
        #expect(!AgentRun.foundSomething("list_files", "site/src/main.rs"))
    }

    @Test("même recherche refaite alors qu'elle trouve : l'agent apprend que la demande existe peut-être déjà")
    func existing() async {
        let (run, llm) = build("fn faq")
        await run.run()
        let p = prompts(llm)
        // Plus jamais « ça n'existe pas » quand la recherche a trouvé.
        #expect(!p.contains { $0.contains("N'EXISTE PAS") })
        #expect(p.contains { $0.contains("EXISTE PEUT-ÊTRE DÉJÀ") })
        #expect(p.contains { $0.contains("tes recherches TROUVENT") })
        #expect(run.summary.contains("existe déjà"))
        #expect(!run.steps.contains { $0.text.contains("en boucle") })
    }

    @Test("même recherche refaite sans rien trouver : toujours « n'existe pas »")
    func missing() async {
        let (run, llm) = build("compare_versions")
        await run.run()
        let p = prompts(llm)
        #expect(p.contains { $0.contains("N'EXISTE PAS") })
        #expect(!p.contains { $0.contains("EXISTE PEUT-ÊTRE DÉJÀ") })
        #expect(run.steps.last?.text.contains("en boucle") == true)
        // La réponse recopiée n'est pas renvoyée : une seule copie de l'action,
        // une seule relance (la dernière) sous son résultat.
        let last = llm.messages(llm.count - 1)
        let copies = last.filter { $0["role"] == "assistant" && $0["content"]?.contains("compare_versions") == true }
        #expect(copies.count == 1)
        #expect(last.last?["content"]?.components(separatedBy: "ACTION DÉJÀ FAITE").count == 2)
    }

    @Test("repeatNudge : la réponse recopiée est retirée, la relance rejoint le résultat et remplace la précédente")
    func nudge() {
        var h = [
            LLMMessage("assistant", "cherche FAQ"),
            LLMMessage("user", "Résultat de search_code :\n15 lignes\(AgentRun.reminderMark)rappel"),
            LLMMessage("assistant", "cherche FAQ"),
        ]
        AgentRun.repeatNudge(&h, "relance 1")
        #expect(h.count == 2)
        #expect(h.last?.role == "user")
        #expect(h.last?.content.hasPrefix("Résultat de search_code :\n15 lignes\(AgentRun.repeatMark)") == true)
        #expect(h.last?.content.hasSuffix("relance 1") == true)
        h.append(LLMMessage("assistant", "cherche FAQ"))
        AgentRun.repeatNudge(&h, "relance 2")
        #expect(h.count == 2)
        #expect(h.last?.content.contains("relance 1") == false)
        #expect(h.last?.content.contains("rappel") == false)
        #expect(h.last?.content.hasSuffix("relance 2") == true)
        // Rien à fusionner : la relance est simplement ajoutée.
        var solo = [LLMMessage("assistant", "x")]
        AgentRun.repeatNudge(&solo, "r")
        #expect(solo.map(\.role) == ["assistant", "user"])
    }

    @Test("sans modification ni résultat trouvé, la note reste la même")
    func note() {
        let (run, _) = build("x")
        #expect(run.progressNote().contains("Fais MAINTENANT la première"))
        #expect(!run.progressNote().contains("TROUVENT"))
    }
}
