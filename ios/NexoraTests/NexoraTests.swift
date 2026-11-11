import Foundation
import NexoraKit
import Testing
@testable import Nexora

/// Les réglages et la bibliothèque d'agents de l'app (le cœur est testé dans
/// NexoraKit, sous Linux comme sur macOS).
@MainActor
@Suite("App")
struct AppTests {
    private func freshDefaults() -> UserDefaults {
        let name = "nexora-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("modèle par défaut : Pollinations, sans clé")
    func defaults() {
        let s = SettingsStore(defaults: freshDefaults())
        #expect(s.resolve(nil) == ModelRef.fallback)
        #expect(s.resolve("inconnu::x") == ModelRef.fallback)
        #expect(s.resolve("groq::llama") == ModelRef("groq", "llama"))
        #expect(s.isReady(s.provider("pollinations")!))
        #expect(s.defaultLevel == .moyen)
    }

    @Test("serveurs perso : ajout, modification, suppression")
    func customProviders() {
        let d = freshDefaults()
        let s = SettingsStore(defaults: d)
        var p = s.addCustomProvider()
        p.name = "Mon vLLM"
        s.updateCustom(p)
        #expect(SettingsStore(defaults: d).provider(p.id)?.name == "Mon vLLM")
        s.deleteCustom(p.id)
        #expect(s.provider(p.id) == nil)
    }

    @Test("adresse modifiée d'un fournisseur du catalogue")
    func override() {
        let s = SettingsStore(defaults: freshDefaults())
        s.setBaseUrl("http://10.0.0.2:11434", for: "ollama")
        #expect(s.provider("ollama")?.baseUrl == "http://10.0.0.2:11434")
        s.resetBaseUrl("ollama")
        #expect(s.provider("ollama")?.baseUrl == Catalog.providers.first { $0.id == "ollama" }?.baseUrl)
    }

    @Test("agents : import Markdown, @mention, suppression")
    func agents() throws {
        let lib = AgentLibrary(defaults: freshDefaults())
        let a = try #require(lib.importMarkdown("---\nname: Traducteur Pro\n---\nTu traduis."))
        #expect(lib.named("traducteur-pro")?.id == a.id)
        #expect(lib.agent(a.id)?.category == "Installés")
        lib.delete(a.id)
        #expect(lib.agent(a.id) == nil)
        #expect(lib.all.count == Catalog.builtinAgents.count)
    }

    @Test("lecture à voix haute : sans Markdown ni code")
    func speechClean() {
        let t = SpeechService.clean("# Titre\n**gras** et `code`\n```swift\nlet a = 1\n```\n[lien](https://x.y)")
        #expect(!t.contains("**") && !t.contains("let a") && t.contains("lien") && !t.contains("https"))
    }
}
