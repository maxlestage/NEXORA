import Foundation

/// Des photos jointes à une instruction de l'agent : elles partent avec la
/// demande, une seule fois (le modèle les voit au tour suivant), puis une note les
/// remplace dans l'historique pour ne pas les renvoyer à chaque tour.
extension AgentRun {
    /// Joint les photos en attente au dernier message de l'utilisateur.
    func attachPendingImages() {
        guard !pendingImages.isEmpty, let i = history.lastIndex(where: { $0.role == "user" }) else { return }
        history[i].images += pendingImages.prefix(ChatImages.maxPerMessage)
        pendingImages = []
    }

    /// Remplace les images de l'historique par une note.
    static func forgetImages(_ history: inout [LLMMessage]) {
        for i in history.indices where !history[i].images.isEmpty {
            let n = history[i].images.count
            let note = n > 1 ? "(\(n) photos jointes, déjà vues)" : "(photo jointe, déjà vue)"
            history[i] = LLMMessage(history[i].role, ChatImages.appending(history[i].content, note))
        }
    }
}
