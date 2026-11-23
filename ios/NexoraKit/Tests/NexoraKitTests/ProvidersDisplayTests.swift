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

    @Test func carteModeleParDefaut() {
        let c = ProvidersDisplay.defaultCard(model: "llama-3.3", provider: "Groq", readyCount: 3)
        #expect(c.note == "Groq")
        #expect(c.accessibility == "Modèle par défaut : llama-3.3, Groq. 3 fournisseurs prêts")
        #expect(c.hint == "Touchez pour changer de modèle")
        #expect(ProvidersDisplay.defaultCard(model: "m", provider: "Groq", readyCount: 1).accessibility.hasSuffix("1 fournisseur prêt"))
        let vide = ProvidersDisplay.defaultCard(model: "m", provider: "", readyCount: 0)
        #expect(vide.note == "Ajoutez une clé ci-dessous")
        #expect(vide.accessibility == "Modèle par défaut : m. Aucun fournisseur prêt")
        #expect(c.readyLine == "3 fournisseurs prêts")
        #expect(vide.readyLine == "Aucun fournisseur prêt")
    }

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

    @Test func actionsRapidesEtCleCollee() {
        let groq = ProviderDef(id: "groq", name: "Groq", baseUrl: "https://g", kind: .openai, free: true,
                               keyUrl: "https://console.groq.com/keys", docsUrl: "https://docs")
        #expect(ProvidersDisplay.quickActions(groq, hasKey: false) == [.getKey, .pasteKey, .docs])
        #expect(ProvidersDisplay.quickActions(groq, hasKey: true) == [.docs])
        let bare = ProviderDef(id: "x", name: "X", baseUrl: "https://x", kind: .openai)
        #expect(ProvidersDisplay.quickActions(bare, hasKey: false) == [.pasteKey])
        let local = ProviderDef(id: "o", name: "Ollama", baseUrl: "http://o", kind: .ollama, needsKey: false, local: true)
        #expect(ProvidersDisplay.quickActions(local, hasKey: false).isEmpty)
        #expect(ProvidersDisplay.getKeyLabel(groq) == "Clé gratuite")
        #expect(ProvidersDisplay.getKeyLabel(bare) == "Obtenir une clé")
        #expect(ProvidersDisplay.pastedKey("  gsk_abc123XYZ\n") == "gsk_abc123XYZ")
        #expect(ProvidersDisplay.pastedKey(nil) == nil)
        #expect(ProvidersDisplay.pastedKey("court") == nil)
        #expect(ProvidersDisplay.pastedKey("voici ma clé secrète") == nil)
        #expect(ProvidersDisplay.pastedKey("https://console.groq.com/keys") == nil)
        #expect(ProvidersDisplay.pastedKey(String(repeating: "a", count: 513)) == nil)
        #expect(ProvidersDisplay.pasteToast(name: "Groq", saved: true) == "Clé enregistrée : Groq est prêt")
        #expect(ProvidersDisplay.pasteToast(name: "Groq", saved: false) == "Copiez d'abord la clé de Groq, puis réessayez")
    }
}

@Suite("Fiche d'un fournisseur")
struct ProviderDetailDisplayTests {
    private let models = [
        ModelInfo("gpt-4o", detail: "Polyvalent"), ModelInfo("gpt-4o-mini", free: true),
        ModelInfo("o3", detail: "Raisonnement poussé"), ModelInfo("llama-3.3-70b"),
    ]

    @Test func aideRepliéeUneFoisConfiguré() {
        let groq = ProviderDef(id: "groq", name: "Groq", baseUrl: "https://g", kind: .openai, description: "")
        let ollama = ProviderDef(id: "ollama", name: "Ollama", baseUrl: "http://o", kind: .ollama, needsKey: false, local: true, description: "")
        #expect(!ProviderDetailDisplay.helpFolded(groq, hasKey: false, modelCount: 20))
        #expect(ProviderDetailDisplay.helpFolded(groq, hasKey: true, modelCount: 0))
        #expect(!ProviderDetailDisplay.helpFolded(ollama, hasKey: false, modelCount: 0))
        #expect(ProviderDetailDisplay.helpFolded(ollama, hasKey: false, modelCount: 3))
    }

    @Test func collerLaCleEtListeVide() {
        #expect(ProviderDetailDisplay.showsPaste(key: ""))
        #expect(ProviderDetailDisplay.showsPaste(key: "  \n"))
        #expect(!ProviderDetailDisplay.showsPaste(key: "sk-abc"))
        #expect(ProviderDetailDisplay.emptyModels(needsKey: true, hasKey: false).contains("collez d'abord la clé"))
        #expect(ProviderDetailDisplay.emptyModels(needsKey: true, hasKey: true).contains("chargez la liste"))
        #expect(ProviderDetailDisplay.emptyModels(needsKey: false, hasKey: false) == ProviderDetailDisplay.emptyModels(needsKey: true, hasKey: true))
    }

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

    @Test func ligneDUnModeleLueParVoiceOver() {
        #expect(ProviderDetailDisplay.modelAccessibility(id: "gpt-4o", detail: "128k de contexte", free: true, isDefault: true)
            == "gpt-4o, 128k de contexte, gratuit, modèle par défaut")
        #expect(ProviderDetailDisplay.modelAccessibility(id: "o3", detail: nil, free: false, isDefault: false) == "o3")
        #expect(ProviderDetailDisplay.modelAccessibility(id: "o3", detail: "  ", free: true, isDefault: false) == "o3, gratuit")
        #expect(ProviderDetailDisplay.modelHint(isDefault: true).isEmpty)
        #expect(ProviderDetailDisplay.modelHint(isDefault: false).contains("modèle par défaut"))
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
    }

    @Test func enregistrementEnQuittantEtSuppression() {
        #expect(!ProviderDetailDisplay.unsaved(key: "", storedKey: nil, url: "http://a", baseUrl: "http://a"))
        #expect(!ProviderDetailDisplay.unsaved(key: " sk-1\n", storedKey: "sk-1", url: "http://a ", baseUrl: "http://a"))
        #expect(ProviderDetailDisplay.unsaved(key: "sk-2", storedKey: "sk-1", url: "http://a", baseUrl: "http://a"))
        #expect(ProviderDetailDisplay.unsaved(key: "sk-1", storedKey: nil, url: "http://a", baseUrl: "http://a"))
        #expect(ProviderDetailDisplay.unsaved(key: "", storedKey: "sk-1", url: "http://a", baseUrl: "http://a"))
        #expect(ProviderDetailDisplay.unsaved(key: "", storedKey: nil, url: "http://b", baseUrl: "http://a"))
        #expect(ProviderDetailDisplay.deleteConfirmation(name: "Mon PC", isDefault: false)
                == "« Mon PC » et sa clé seront supprimés.")
        #expect(ProviderDetailDisplay.deleteConfirmation(name: " ", isDefault: true)
                == "« Serveur perso » et sa clé seront supprimés. C'est votre modèle par défaut : un autre sera utilisé à sa place.")
        #expect(ProviderDetailDisplay.testSuccess(model: "o3", ms: 3000, answer: "") == "Ça marche : o3 a répondu en 3,0 s.")
    }

    @Test func adresseDUnNouveauServeur() {
        typealias D = ProviderDetailDisplay
        #expect(D.serverAddress("  http://192.168.1.10:8080/v1/ ") == "http://192.168.1.10:8080/v1")
        #expect(D.serverAddress("192.168.1.10:8080/v1") == "http://192.168.1.10:8080/v1")
        #expect(D.serverAddress("https://api.exemple.fr/v1") == "https://api.exemple.fr/v1")
        #expect(D.serverAddress("localhost:11434") == "http://localhost:11434")
        #expect(D.serverAddress("") == nil)
        #expect(D.serverAddress("http://") == nil)
        #expect(D.serverAddress("ftp://serveur/v1") == nil)
        #expect(D.serverAddress("http://mon serveur/v1") == nil)
        #expect(D.serverAddressHint("http://192.168.1.10:8080/v1") == nil)
        #expect(D.serverAddressHint(" ")?.hasPrefix("Indiquez") == true)
        #expect(D.serverAddressHint("ftp://x")?.hasPrefix("Adresse invalide") == true)
        #expect(D.serverName("  Mon Mac ", address: "http://10.0.0.2:8080") == "Mon Mac")
        #expect(D.serverName(" ", address: "http://10.0.0.2:8080") == "10.0.0.2")
    }

    @Test func adresseModifieeDansLaFiche() {
        typealias D = ProviderDetailDisplay
        let base = "https://api.openai.com/v1"
        #expect(D.editedAddress("", current: base) == nil)
        #expect(D.editedAddress("https://api.openai.com/v1/", current: base) == nil)
        #expect(D.editedAddress(" https://api.openai.com/v1 ", current: base) == nil)
        #expect(D.editedAddress("htps//mauvais adresse", current: base) == nil)
        #expect(D.editedAddress("192.168.1.20:11434", current: "http://localhost:11434")
                == "http://192.168.1.20:11434")
        #expect(D.editedAddress("https://proxy.exemple.fr/v1/", current: base) == "https://proxy.exemple.fr/v1")
    }

    @Test func modeleAjouteALaMain() {
        typealias D = ProviderDetailDisplay
        let list = ["gpt-4o", "gpt-4o-mini"]
        #expect(D.manualModel("  o3-pro \n", existing: list) == "o3-pro")
        #expect(D.manualModel("`o3-pro`", existing: list) == "o3-pro")
        #expect(D.manualModel("", existing: list) == nil)
        #expect(D.manualModel("gpt 4o", existing: list) == nil)
        #expect(D.manualModel(" gpt-4o ", existing: list) == nil)
        #expect(D.manualModelHint("", existing: list) == nil)
        #expect(D.manualModelHint("o3-pro", existing: list) == nil)
        #expect(D.manualModelHint("gpt-4o", existing: list) == "gpt-4o est déjà dans la liste.")
        #expect(D.manualModelHint("gpt 4o", existing: list)?.hasPrefix("Un id") == true)
    }
}
