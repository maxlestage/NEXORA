import Foundation
import Observation

/// L'onglet affiché : les écrans peuvent en changer (ex. « Premiers pas » ouvre
/// l'onglet Modèles). Fourni par `HomeShell` ; facultatif pour les écrans.
@MainActor
@Observable
final class AppNavigation {
    var tab: AppTab = .chat

    init() {}
}
