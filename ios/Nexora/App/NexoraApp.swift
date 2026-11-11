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
            HomeShell()
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
