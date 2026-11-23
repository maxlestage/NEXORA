import Testing
@testable import NexoraKit

@Suite("Agents cloud")
struct CloudAgentsDisplayTests {
    @Test func etatDesMissions() {
        #expect(CloudAgentsDisplay.runState(status: "in_progress", conclusion: nil) == .running)
        #expect(CloudAgentsDisplay.runState(status: nil, conclusion: nil) == .running)
        #expect(CloudAgentsDisplay.runState(status: "completed", conclusion: "success") == .success)
        #expect(CloudAgentsDisplay.runState(status: "completed", conclusion: "cancelled") == .cancelled)
        #expect(CloudAgentsDisplay.runState(status: "completed", conclusion: "failure") == .failure)
        #expect(CloudAgentsDisplay.runDetail(name: "NEXORA Claude", status: "completed", conclusion: "success")
            == "Réussie · NEXORA Claude")
        #expect(CloudAgentsDisplay.runDetail(name: nil, status: "queued", conclusion: nil) == "En cours")
        #expect(CloudAgentsDisplay.runAccessibility(title: "Mode sombre", name: "NEXORA Aider",
                                                    status: "completed", conclusion: "failure")
            == "Mode sombre, Échouée · NEXORA Aider")
    }

    @Test func actionsEtMessages() {
        #expect(CloudAgentsDisplay.primaryAction(installed: false) == "Installer")
        #expect(CloudAgentsDisplay.primaryAction(installed: true) == "Lancer")
        #expect(CloudAgentsDisplay.installError("Resource not accessible: workflow scope").hasSuffix("droit « workflow »."))
        #expect(CloudAgentsDisplay.installError("Hors ligne") == "Hors ligne")
        #expect(CloudAgentsDisplay.loadProblem("Hors ligne").hasSuffix("Hors ligne"))
        #expect(!CloudAgentsDisplay.canLaunch("  \n "))
        #expect(CloudAgentsDisplay.canLaunch("ajoute un README"))
        #expect(CloudAgentsDisplay.intro.count < 120)
    }

    @Test func modeleAiderVerifie() {
        let d = CloudAgentsDisplay.defaultAiderModel
        // Champ vidé : le modèle par défaut part (avant : un modèle vide).
        #expect(CloudAgentsDisplay.aiderModel("  ") == d)
        #expect(CloudAgentsDisplay.aiderModelHint("") == nil)
        // Collé avec guillemets ou « ` » : nettoyé.
        #expect(CloudAgentsDisplay.aiderModel(" `openai/gpt-4o` ") == "openai/gpt-4o")
        #expect(CloudAgentsDisplay.aiderModel("\"deepseek/deepseek-chat\"") == "deepseek/deepseek-chat")
        // Espace au milieu : refusé, avec un message.
        #expect(CloudAgentsDisplay.aiderModel("gpt 4o") == nil)
        #expect(CloudAgentsDisplay.aiderModelHint("gpt 4o") != nil)
    }

    @Test func instructionCommenceeProtegee() {
        // Rien d'écrit (ou seulement des espaces) : la fenêtre se ferme d'un geste, sans question.
        #expect(!CloudAgentsDisplay.losesInstruction(""))
        #expect(!CloudAgentsDisplay.losesInstruction("  \n "))
        // Une instruction commencée : on demande avant de la perdre.
        #expect(CloudAgentsDisplay.losesInstruction("ajoute un mode sombre"))
        #expect(CloudAgentsDisplay.discardQuestion.hasSuffix("sera perdu."))
        #expect(CloudAgentsDisplay.discardQuestion.count < 70)
    }

    @Test func appelEnCoursEtRefusDuLancement() {
        #expect(CloudAgentsDisplay.busyLabel(.installing, installed: false) == "Installation…")
        #expect(CloudAgentsDisplay.busyLabel(.installing, installed: true) == "Mise à jour…")
        #expect(CloudAgentsDisplay.busyLabel(.launching, installed: true) == "Lancement…")
        let ancien = CloudAgentsDisplay.launchError(
            "Workflow does not have 'workflow_dispatch' trigger", agent: "Aider", branch: "main")
        #expect(ancien.hasPrefix("GitHub n'a pas lancé Aider : Workflow does not"))
        #expect(ancien.hasSuffix("« Mettre à jour » dans le menu « … » de l'agent."))
        let absent = CloudAgentsDisplay.launchError("Not Found", agent: "Aider", branch: "dev")
        #expect(absent.hasSuffix("installé sur la branche dev."))
        #expect(CloudAgentsDisplay.launchError("Hors ligne", agent: "Aider", branch: "main")
            == "GitHub n'a pas lancé Aider : Hors ligne")
    }

    @Test func clesEtOrdre() {
        let keys = ["ANTHROPIC_API_KEY"]
        #expect(CloudAgentsDisplay.secretLine(keys, present: nil) == "Clé à ajouter : ANTHROPIC_API_KEY")
        #expect(CloudAgentsDisplay.secretLine(keys, present: ["ANTHROPIC_API_KEY"]) == "Clé ajoutée : ANTHROPIC_API_KEY")
        #expect(CloudAgentsDisplay.secretLine(keys, present: []) == "Clé manquante : ANTHROPIC_API_KEY")
        #expect(CloudAgentsDisplay.secretLine(["A", "B"], present: ["A"]) == "Clé manquante : B")
        #expect(CloudAgentsDisplay.secretLine(["A", "B"], present: []) == "Clés manquantes : A · B")
        #expect(CloudAgentsDisplay.showsSecretButton(keys, present: nil))
        #expect(CloudAgentsDisplay.showsSecretButton(keys, present: []))
        #expect(!CloudAgentsDisplay.showsSecretButton(keys, present: ["ANTHROPIC_API_KEY"]))
        #expect(!CloudAgentsDisplay.showsSecretButton([], present: nil))
        let agents = Catalog.cloudAgents
        #expect(CloudAgentsDisplay.ordered(agents, installed: nil).map(\.id) == agents.map(\.id))
        if let last = agents.last, agents.count > 1 {
            let sorted = CloudAgentsDisplay.ordered(agents, installed: [last.workflowFile])
            #expect(sorted.first?.id == last.id)
            #expect(sorted.count == agents.count)
        }
    }

    @Test func nomsDesSecrets() async throws {
        let t = FakeTransport([.init(headers: ["content-type": "application/json"],
            body: #"{"total_count":2,"secrets":[{"name":"ANTHROPIC_API_KEY","created_at":"x"},{"name":"GEMINI_API_KEY"}]}"#)])
        let names = try await GitHubAPI(token: "t", transport: t).secretNames("max", "site")
        #expect(names == ["ANTHROPIC_API_KEY", "GEMINI_API_KEY"])
        #expect(t.requests.first?.url?.path == "/repos/max/site/actions/secrets")
    }
}
