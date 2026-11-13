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

@Suite("Fiche d'un fournisseur")
struct ProviderDetailDisplayTests {
    private let models = [
        ModelInfo("gpt-4o", detail: "Polyvalent"), ModelInfo("gpt-4o-mini", free: true),
        ModelInfo("o3", detail: "Raisonnement poussé"), ModelInfo("llama-3.3-70b"),
    ]

    @Test func rechercheEtDefautEnTete() {
        #expect(ProviderDetailDisplay.models(models, query: "", defaultId: "o3").map(\.id)
                == ["o3", "gpt-4o", "gpt-4o-mini", "llama-3.3-70b"])
        #expect(ProviderDetailDisplay.models(models, query: "MINI", defaultId: nil).map(\.id) == ["gpt-4o-mini"])
        #expect(ProviderDetailDisplay.models(models, query: "pousse", defaultId: "gpt-4o").map(\.id) == ["o3"])
        #expect(ProviderDetailDisplay.models(models, query: "zzz", defaultId: "o3").isEmpty)
        #expect(ProviderDetailDisplay.models(models, query: "gpt", defaultId: "absent").map(\.id) == ["gpt-4o", "gpt-4o-mini"])
        #expect(!ProviderDetailDisplay.showsSearch(count: 12))
        #expect(ProviderDetailDisplay.showsSearch(count: 13))
    }

    @Test func adresseEtTest() {
        let cloud = ProviderDef(id: "openai", name: "OpenAI", baseUrl: "https://a", kind: .openai)
        let local = ProviderDef(id: "ollama", name: "Ollama", baseUrl: "http://o", kind: .ollama, needsKey: false, local: true)
        let perso = ProviderDef(id: "c1", name: "Mon serveur", baseUrl: "http://s", kind: .openai, custom: true)
        #expect(!ProviderDetailDisplay.addressInline(cloud, modified: false))
        #expect(ProviderDetailDisplay.addressInline(cloud, modified: true))
        #expect(ProviderDetailDisplay.addressInline(local, modified: false))
        #expect(ProviderDetailDisplay.addressInline(perso, modified: false))
        #expect(ProviderDetailDisplay.duration(ms: 850) == "850 ms")
        #expect(ProviderDetailDisplay.duration(ms: 1234) == "1,2 s")
        #expect(ProviderDetailDisplay.duration(ms: 1960) == "2,0 s")
        #expect(ProviderDetailDisplay.testSuccess(model: "o3", ms: 420, answer: " OK NEXORA \n")
                == "Ça marche : o3 a répondu en 420 ms (« OK NEXORA »).")
        #expect(ProviderDetailDisplay.testSuccess(model: "o3", ms: 3000, answer: "") == "Ça marche : o3 a répondu en 3,0 s.")
    }
}
