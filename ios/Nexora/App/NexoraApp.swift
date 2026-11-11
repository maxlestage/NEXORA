import NexoraKit
import SwiftUI

@main
struct NexoraApp: App {
    @State private var settings: SettingsStore
    @State private var agents: AgentLibrary
    @State private var chats: ChatStore
    @State private var usage: UsageStore
    @State private var github = GitHubSession()
    @State private var speech = SpeechService()

    init() {
        let settings = SettingsStore()
        let agents = AgentLibrary()
        _settings = State(initialValue: settings)
        _agents = State(initialValue: agents)
        let usage = UsageStore()
        let chats = ChatStore(settings: settings, agents: agents)
        chats.usage = usage
        _usage = State(initialValue: usage)
        _chats = State(initialValue: chats)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(agents)
                .environment(chats)
                .environment(github)
                .environment(speech)
                .environment(usage)
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
    @Environment(UsageStore.self) private var usage
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .chat

    var body: some View {
        TabView(selection: $tab) {
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right", value: .chat) {
                ConversationsView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            Tab("Agents", systemImage: "person.2.badge.gearshape", value: .agents) {
                AgentsView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            Tab("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", value: .github) {
                GitHubView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            Tab("Modèles", systemImage: "cpu", value: .models) {
                ProvidersView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            Tab("Réglages", systemImage: "gearshape", value: .settings) {
                SettingsView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sensoryFeedback(.selection, trigger: tab) { _, _ in settings.haptics }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { usage.saveNow() }
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.onboarded }, set: { settings.onboarded = !$0 })) {
            OnboardingView()
        }
    }
}
