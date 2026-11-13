import Testing
@testable import NexoraKit

@Suite("Onglet Modèles")
struct ProvidersDisplayTests {
    private let list = [
        ProviderDef(id: "groq", name: "Groq", baseUrl: "https://g", kind: .openai, free: true, description: "Très rapide"),
        ProviderDef(id: "ollama", name: "Ollama", baseUrl: "http://o", kind: .ollama, needsKey: false, local: true, description: "Modèles sur votre réseau"),
        ProviderDef(id: "openai", name: "OpenAI", baseUrl: "https://a", kind: .openai, description: "GPT"),
        ProviderDef(id: "pollen", name: "Pollen", baseUrl: "https://p", kind: .openai, free: true, needsKey: false, description: "Sans inscription"),
        ProviderDef(id: "c1", name: "Mon serveur", baseUrl: "http://s", kind: .openai, needsKey: false, custom: true),
    ]
    private func ready(_ p: ProviderDef) -> Bool { !p.needsKey || p.id == "groq" }

    @Test func filtresEtRecherche() {
        #expect(ProvidersDisplay.filter(list, filter: "all", query: "", isReady: ready).count == 5)
        #expect(ProvidersDisplay.filter(list, filter: "free", query: "", isReady: ready).map(\.id) == ["groq", "pollen"])
        #expect(ProvidersDisplay.filter(list, filter: "local", query: "", isReady: ready).map(\.id) == ["ollama", "c1"])
        #expect(ProvidersDisplay.filter(list, filter: "ready", query: "", isReady: ready).map(\.id) == ["groq", "ollama", "pollen", "c1"])
        #expect(ProvidersDisplay.filter(list, filter: "all", query: " RESEAU ", isReady: ready).map(\.id) == ["ollama"])
        #expect(ProvidersDisplay.filter(list, filter: "free", query: "openai", isReady: ready).isEmpty)
        #expect(ProvidersDisplay.filterLabel("ready", label: "Prêts", providers: list, isReady: ready) == "Prêts · 4")
        #expect(ProvidersDisplay.filterLabel("all", label: "Tous", providers: list, isReady: ready) == "Tous")
    }

    @Test func sectionsPretsDAbord() {
        let s = ProvidersDisplay.sections(list, isReady: ready)
        #expect(s.map(\.title) == ["Prêts (4)", "À configurer (1)"])
        #expect(s[0].ids == ["groq", "ollama", "pollen", "c1"])
        #expect(s[1].ids == ["openai"])
        // Un seul groupe : pas d'en-tête ; liste vide : aucune section.
        let seul = ProvidersDisplay.sections(Array(list.prefix(2)), isReady: { _ in true })
        #expect(seul == [ProvidersDisplay.Section(title: "", ids: ["groq", "ollama"])])
        #expect(ProvidersDisplay.sections([], isReady: ready).isEmpty)
    }

    @Test func etiquettesCourtes() {
        #expect(ProvidersDisplay.tags(list[0]) == ["gratuit"])
        #expect(ProvidersDisplay.tags(list[1]) == ["local"])
        #expect(ProvidersDisplay.tags(list[2]).isEmpty)
        #expect(ProvidersDisplay.tags(list[3]) == ["gratuit", "sans clé"])
        #expect(ProvidersDisplay.tags(list[4]) == ["perso"])
        #expect(ProvidersDisplay.accessibility(list[2], ready: false) == "OpenAI, clé requise")
        #expect(ProvidersDisplay.accessibility(list[0], ready: true) == "Groq, prêt, gratuit")
    }
}
