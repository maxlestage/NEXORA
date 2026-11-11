import NexoraKit
import SwiftUI
import UIKit

/// Tout ce qui se règle dans NEXORA, avec un aperçu en direct
/// (`ui/settings/personalize_screen.dart`).
struct PersonalizeView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var pickLevel = false
    @State private var importing = false
    @State private var importText = ""
    @State private var toast: Toast?
    @State private var name = ""
    @State private var about = ""
    @State private var style = ""
    @State private var loaded = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section { preview }

            Section("Couleurs") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(Theme.palettes) { p in
                        Swatch(palette: p, selected: settings.accent == p.id) { settings.accent = p.id }
                    }
                }
                .padding(.vertical, 6)
                Picker("Thème", selection: $settings.theme) {
                    Label("Sombre", systemImage: "moon.fill").tag("dark")
                    Label("Clair", systemImage: "sun.max.fill").tag("light")
                    Label("Auto", systemImage: "iphone").tag("system")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.oledBlack) {
                    VStack(alignment: .leading) {
                        Text("Noir pur (écran OLED)")
                        Text("Économise la batterie en thème sombre").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Taille du texte")
                        Spacer()
                        Text("\(Int((settings.textScale * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.textScale, in: 0.85...1.3, step: 0.05)
                        .accessibilityValue("\(Int((settings.textScale * 100).rounded())) %")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Animations")
                    Picker("Animations", selection: $settings.animations) {
                        Text("Toutes").tag("full")
                        Text("Douces").tag("reduced")
                        Text("Aucune").tag("off")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            } header: {
                Text("Affichage")
            } footer: {
                Text("Le logo 3D, les fonds animés, les cartes inclinables et les apparitions en cascade. « Réduire les animations » d'iOS est toujours respecté.")
            }

            Section("Conversations") {
                Button {
                    pickLevel = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Effort par défaut").foregroundStyle(.primary)
                            Text("\(settings.defaultLevel.emoji) \(settings.defaultLevel.label) · \(settings.defaultLevel.summary)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        LevelBars(level: settings.defaultLevel, color: Theme.accent(settings.accent))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style des messages envoyés")
                    HStack(spacing: 8) {
                        ForEach([("gradient", "Contour"), ("filled", "Plein"), ("minimal", "Discret")], id: \.0) { value, label in
                            Button {
                                settings.bubbleStyle = value
                            } label: {
                                VStack(spacing: 6) {
                                    UserBubble(text: "Salut", style: value, accent: settings.accent, radius: 18)
                                    Text(label).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(settings.bubbleStyle == value ? Theme.accent(settings.accent) : Color.gray.opacity(0.3), lineWidth: settings.bubbleStyle == value ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(settings.bubbleStyle == value ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mémoire envoyée au modèle")
                    Text("Seuls les messages récents repartent à chaque question : réponses plus rapides et moins chères dans les longues conversations.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Mémoire", selection: Binding(
                        get: { Preferences.memoryChoices.contains(settings.contextTokens) ? settings.contextTokens : 32000 },
                        set: { settings.contextTokens = $0 }
                    )) {
                        Text("Courte").tag(8000)
                        Text("Normale").tag(32000)
                        Text("Longue").tag(128_000)
                        Text("Tout").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(ChatDisplay.memoryCaption(settings.contextTokens)).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Créativité (température)")
                        Spacer()
                        Text(String(format: "%.1f", settings.temperature)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.temperature, in: 0...1.5, step: 0.1)
                }
                Toggle(isOn: $settings.sendOnEnter) {
                    VStack(alignment: .leading) {
                        Text("Entrée pour envoyer")
                        Text("Pratique avec un clavier ou sur iPad").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.showThinking) {
                    VStack(alignment: .leading) {
                        Text("Afficher le raisonnement")
                        Text("Claude, DeepSeek R1, Qwen3, gpt-oss…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Retour haptique", isOn: $settings.haptics)
            }

            Section("Voix") {
                Toggle(isOn: $settings.speakReplies) {
                    VStack(alignment: .leading) {
                        Text("Lire toutes les réponses")
                        Text("Sinon, la réponse est lue quand vous avez parlé (micro) ou quand vous le demandez (« réponds-moi à voix haute »).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Envoyer à la fin de la dictée", isOn: $settings.voiceAutoSend)
                Toggle(isOn: $settings.voiceConversation) {
                    VStack(alignment: .leading) {
                        Text("Conversation vocale")
                        Text("Après la réponse lue, l'assistant vous écoute de nouveau : parlez sans toucher l'écran.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Vitesse de lecture")
                        Spacer()
                        Text(settings.voiceRate < 0.45 ? "Lente" : settings.voiceRate > 0.55 ? "Rapide" : "Normale").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.voiceRate, in: 0.3...0.7, step: 0.05)
                }
            }

            Section("Votre assistant") {
                TextField("Nom de l'assistant", text: $name)
                    .onSubmit(saveAssistant)
                Toggle(isOn: $settings.customInstructions) {
                    VStack(alignment: .leading) {
                        Text("Instructions personnelles")
                        Text("Ajoutées à chaque conversation, avec ou sans agent").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if settings.customInstructions {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ce que l'assistant doit savoir sur vous").font(.caption).foregroundStyle(.secondary)
                        TextField("Ex. : je suis développeur Flutter, je travaille sur iPhone, je débute en Rust…", text: $about, axis: .vertical)
                            .lineLimit(2...6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment il doit répondre").font(.caption).foregroundStyle(.secondary)
                        TextField("Ex. : tutoie-moi, sois bref, donne toujours un exemple de code commenté…", text: $style, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                Button("Enregistrer", systemImage: "checkmark", action: saveAssistant)
            }

            Section("Onglets") {
                ForEach([("agents", "Agents", "person.2"), ("github", "Code (GitHub)", "chevron.left.forwardslash.chevron.right")], id: \.0) { id, label, icon in
                    Toggle(isOn: Binding(get: { !settings.hiddenTabs.contains(id) }, set: { settings.setTabHidden(id, !$0) })) {
                        Label("Afficher l'onglet \(label)", systemImage: icon)
                    }
                }
            }

            Section {
                Button("Exporter", systemImage: "square.and.arrow.up") { export() }
                Button("Importer", systemImage: "square.and.arrow.down") {
                    importText = ""
                    importing = true
                }
                Button("Remettre par défaut", systemImage: "arrow.counterclockwise") { reset() }
            }
        }
        .navigationTitle("Personnaliser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Exporter mes réglages", systemImage: "square.and.arrow.up") { export() }
                    Button("Importer des réglages", systemImage: "square.and.arrow.down") {
                        importText = ""
                        importing = true
                    }
                    Button("Tout remettre par défaut", systemImage: "arrow.counterclockwise") { reset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Exporter, importer, remettre par défaut")
            }
        }
        .sheet(isPresented: $pickLevel) {
            NavigationStack {
                EffortPage(current: settings.defaultLevel, title: "Effort par défaut") { l in
                    settings.defaultLevel = l
                    pickLevel = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { pickLevel = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $importing) { importSheet }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = settings.assistantName
            about = settings.aboutMe
            style = settings.responseStyle
        }
        .toast($toast)
    }

    /// L'aperçu en direct : couleurs, logo, messages, niveau.
    private var preview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NexusOrb(size: 72, satellites: 6, interactive: false)
                VStack(alignment: .leading, spacing: 2) {
                    GradientText(settings.assistantName, font: .title3.weight(.black), tracking: 2)
                    Text("Aperçu · \(Theme.palette(settings.accent).name)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                LevelBars(level: settings.defaultLevel, color: Theme.accent(settings.accent))
            }
            HStack {
                Spacer()
                UserBubble(text: "Peux-tu m'aider à coder ?", style: settings.bubbleStyle, accent: settings.accent, radius: 18)
            }
            HStack {
                Text("Bien sûr ! Par quoi commençons-nous ? \(settings.defaultLevel.emoji)")
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collez ici les réglages exportés", text: $importText, axis: .vertical)
                        .font(.caption.monospaced())
                        .lineLimit(6...12)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Importer des réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { importing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer") {
                        importing = false
                        guard !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        if settings.importPreferences(importText) {
                            reloadFields()
                            toast = Toast(text: "Réglages importés ✅")
                        } else {
                            toast = Toast(text: "Texte invalide : collez des réglages exportés.", error: true)
                        }
                    }
                }
            }
        }
    }

    private func saveAssistant() {
        settings.setAssistantName(name)
        settings.aboutMe = about
        settings.responseStyle = style
        name = settings.assistantName
        toast = Toast(text: "Assistant enregistré")
    }

    private func export() {
        UIPasteboard.general.string = settings.exportPreferences()
        toast = Toast(text: "Réglages copiés (sans vos clés)")
    }

    private func reset() {
        settings.resetPersonalization()
        reloadFields()
        toast = Toast(text: "Personnalisation remise à zéro")
    }

    private func reloadFields() {
        name = settings.assistantName
        about = settings.aboutMe
        style = settings.responseStyle
    }
}

/// Un jeu de couleurs à choisir.
private struct Swatch: View {
    let palette: Theme.Palette
    let selected: Bool
    let onTap: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 3))
                    .overlay { if selected { Image(systemName: "checkmark").foregroundStyle(.white).fontWeight(.bold) } }
                    .shadow(color: selected ? palette.colors[0].opacity(0.5) : .clear, radius: 7)
                    .animation(.easeOut(duration: 0.25), value: selected)
                Text(palette.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new && settings.haptics }
        .accessibilityLabel("Couleurs \(palette.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
