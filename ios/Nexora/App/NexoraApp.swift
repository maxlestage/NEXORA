import NexoraKit
import SwiftUI

@main
struct NexoraApp: App {
    @State private var settings: SettingsStore
    @State private var agents: AgentLibrary
    @State private var chats: ChatStore
    @State private var github = GitHubSession()
    @State private var speech = SpeechService()

    init() {
        let settings = SettingsStore()
        let agents = AgentLibrary()
        _settings = State(initialValue: settings)
        _agents = State(initialValue: agents)
        _chats = State(initialValue: ChatStore(settings: settings, agents: agents))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(agents)
                .environment(chats)
                .environment(github)
                .environment(speech)
                .preferredColorScheme(settings.colorScheme)
                .tint(Theme.accent(settings.accent))
                .onAppear { chats.speech = speech }
        }
    }
}

/// Les onglets de l'app.
enum AppTab: Hashable {
    case chat, agents, github, models, settings
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var tab: AppTab = .chat

    var body: some View {
        TabView(selection: $tab) {
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right", value: .chat) {
                ConversationsView()
            }
            Tab("Agents", systemImage: "person.2.badge.gearshape", value: .agents) {
                AgentsView()
            }
            Tab("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", value: .github) {
                GitHubView()
            }
            Tab("Modèles", systemImage: "cpu", value: .models) {
                ProvidersView()
            }
            Tab("Réglages", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sensoryFeedback(.selection, trigger: tab) { _, _ in settings.haptics }
        .fullScreenCover(isPresented: Binding(get: { !settings.onboarded }, set: { settings.onboarded = !$0 })) {
            OnboardingView()
        }
    }
}
