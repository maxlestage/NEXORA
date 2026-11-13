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
}
