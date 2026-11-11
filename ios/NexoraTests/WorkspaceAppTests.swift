import Foundation
import NexoraKit
import Testing
@testable import Nexora

/// L'atelier côté app : réglages de la CI, branchement des sessions aux réglages
/// (la logique des sessions et des routines est testée dans NexoraKit).
@MainActor
@Suite("Atelier (app)")
struct WorkspaceAppTests {
    private func freshDefaults() -> UserDefaults {
        let name = "nexora-workspace-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set(true, forKey: FlutterMigration.doneKey)
        return d
    }

    @Test("CI et fusion automatiques : actives par défaut, enregistrées, reprises de l'app Flutter")
    func autoCi() {
        let d = freshDefaults()
        let s = SettingsStore(defaults: d)
        #expect(s.agentAutoCi)
        #expect(s.agentAutoMerge)
        s.agentAutoMerge = false
        #expect(SettingsStore(defaults: d).agentAutoMerge == false)

        let f = freshDefaults()
        f.set(false, forKey: "flutter.agent_auto_ci")
        #expect(SettingsStore(defaults: f).agentAutoCi == false)
    }

    @Test("sessions : branchées aux réglages, au compte et aux agents")
    func host() async {
        let d = freshDefaults()
        let settings = SettingsStore(defaults: d)
        settings.agentAutoCi = false
        settings.defaultLevel = .eleve
        let store = SessionStore(
            settings: settings, agents: AgentLibrary(defaults: d), github: GitHubSession(),
            usage: UsageStore(defaults: d, loadCatalog: false), files: MemorySessionFiles(), background: nil
        )
        await store.ready()
        #expect(store.sessions.isEmpty)
        #expect(!store.loading)
        #expect(store.host.agentAutoCi == false)
        #expect(store.host.defaultLevel == .eleve)
        #expect(store.host.provider("groq")?.id == "groq")
        #expect(store.host.agent(nil) == nil)
        // Plus rien à essayer : pas de repli.
        let all = Set(settings.providers.flatMap { p in settings.models(for: p).map { ModelRef(p.id, $0.id).key } })
            .union(["pollinations::openai", "pollinations::openai-fast", settings.resolve(settings.defaultModel).key])
        #expect(await store.host.fallback(LLMError("x"), all) == nil)
        // Un modèle gratuit sans clé reste possible.
        let pick = await store.host.fallback(LLMError("x"), [settings.resolve(settings.defaultModel).key])
        #expect(pick != nil)
    }
}
