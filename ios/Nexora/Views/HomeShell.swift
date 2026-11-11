import NexoraKit
import SwiftUI

/// La navigation principale (`ui/home_shell.dart`) : cinq onglets (barre en bas,
/// barre latérale sur iPad), dont Agents et Code peuvent être masqués dans
/// Personnaliser ; l'accueil au premier lancement, puis les nouveautés une fois
/// après chaque mise à jour. Remplace `RootView`.
struct HomeShell: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage
    @Environment(SessionStore.self) private var sessions
    @Environment(RoutineBook.self) private var routines
    @Environment(GitHubSession.self) private var github
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation()
    @State private var whatsNew: [Release] = []

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.chat) {
                ConversationsView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            if !settings.hiddenTabs.contains("agents") {
                Tab("Agents", systemImage: "person.2.badge.gearshape", value: AppTab.agents) {
                    AgentsView()
                        .safeAreaInset(edge: .bottom) { CreditBar() }
                }
            }
            if !settings.hiddenTabs.contains("github") {
                Tab("Code", systemImage: "chevron.left.forwardslash.chevron.right", value: AppTab.github) {
                    GitHubView()
                        .safeAreaInset(edge: .bottom) { CreditBar() }
                }
            }
            Tab("Modèles", systemImage: "cpu", value: AppTab.models) {
                ProvidersView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
            Tab("Réglages", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
                    .safeAreaInset(edge: .bottom) { CreditBar() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(navigation)
        .dynamicTypeSize(settings.dynamicTypeSize)
        .sensoryFeedback(.selection, trigger: navigation.tab) { _, _ in settings.haptics }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                usage.saveNow()
                // Les sessions de l'agent : enregistrées tout de suite (l'app peut
                // être fermée en arrière-plan).
                sessions.saveNow()
            } else {
                // De retour : les passages de routine manqués sont rattrapés.
                Task { await routines.check() }
            }
        }
        // Le compte GitHub a changé : les sessions utilisent le nouveau.
        .onChange(of: github.token) { sessions.githubChanged() }
        // Un onglet masqué pendant qu'il est affiché : retour au chat.
        .onChange(of: settings.hiddenTabs) {
            if (navigation.tab == .agents && settings.hiddenTabs.contains("agents"))
                || (navigation.tab == .github && settings.hiddenTabs.contains("github")) {
                navigation.tab = .chat
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.onboarded }, set: { if !$0 { settings.finishOnboarding() } })) {
            OnboardingView()
        }
        .sheet(isPresented: Binding(get: { !whatsNew.isEmpty && settings.onboarded }, set: { if !$0 { whatsNew = [] } })) {
            WhatsNewSheet(releases: whatsNew)
                .presentationDetents([.medium, .large])
        }
        .task {
            // Après une mise à jour : les nouveautés, une fois.
            whatsNew = WhatsNewSheet.pending(settings)
            // Les routines du téléphone : vérifiées toutes les 30 s (les passages
            // manqués sont rattrapés une fois, au démarrage).
            routines.startTicking()
            // Les derniers modèles (au plus une fois toutes les 6 heures).
            await settings.refreshCatalog()
        }
    }
}
