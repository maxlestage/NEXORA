import Foundation
import NexoraKit
import Testing
@testable import Nexora

/// Les réglages repris de l'app Flutter : personnalisation, export et import,
/// reprise des préférences Flutter.
@MainActor
@Suite("App : réglages")
struct ParityAppTests {
    private func freshDefaults() -> UserDefaults {
        let name = "nexora-parity-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("valeurs par défaut de l'app Flutter")
    func defaults() {
        let s = SettingsStore(defaults: freshDefaults())
        #expect(s.theme == "dark")
        #expect(!s.customInstructions)
        #expect(s.animations == "full" && s.bubbleStyle == "gradient")
        #expect(s.voiceConversation && s.voiceAutoSend && s.voiceRate == 0.5)
        #expect(s.textScale == 1 && s.hiddenTabs.isEmpty)
    }

    @Test("personnalisation : export, remise à zéro, import")
    func roundTrip() {
        let s = SettingsStore(defaults: freshDefaults())
        s.setAssistantName("  Jarvis ")
        s.customInstructions = true
        s.aboutMe = "Développeur Flutter"
        s.accent = 3
        s.defaultLevel = .eleve
        s.setTabHidden("github", true)
        #expect(s.assistantName == "Jarvis")
        #expect(s.personalSystem().contains("Développeur Flutter"))
        let exported = s.exportPreferences()
        #expect(!exported.contains("key:"))
        s.resetPersonalization()
        #expect(s.assistantName == "NEXORA" && s.accent == 0 && s.hiddenTabs.isEmpty)
        #expect(s.importPreferences(exported))
        #expect(s.assistantName == "Jarvis" && s.accent == 3 && s.defaultLevel == .eleve && s.hiddenTabs == ["github"])
        #expect(!s.importPreferences("n'importe quoi"))
    }

    @Test("les préférences de l'app Flutter sont reprises une fois")
    func migration() {
        let d = freshDefaults()
        d.set("groq::llama", forKey: "flutter.default_model")
        d.set(#"["groq::llama"]"#, forKey: "flutter.favorite_models")
        d.set(true, forKey: "flutter.onboarded")
        let s = SettingsStore(defaults: d)
        #expect(s.defaultModel == "groq::llama")
        #expect(s.favorites == ["groq::llama"])
        #expect(s.onboarded)
        // Une seconde ouverture ne réécrit rien.
        s.defaultModel = "gemini::x"
        #expect(SettingsStore(defaults: d).defaultModel == "gemini::x")
    }

    @Test("adresse modifiée : remise à l'origine avec les modèles ajoutés")
    func resetProvider() {
        let s = SettingsStore(defaults: freshDefaults())
        s.setBaseUrl("http://10.0.0.2:11434", for: "ollama")
        s.addModel("mon-modele", to: "ollama")
        #expect(s.isModified("ollama"))
        #expect(s.models(for: s.provider("ollama")!).first?.id == "mon-modele")
        s.resetProvider("ollama")
        #expect(!s.isModified("ollama"))
    }
}
