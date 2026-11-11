import Foundation
import NexoraKit

/// Le journal d'une session (les étapes regroupées et le nombre d'actions),
/// recalculé seulement quand les étapes changent : l'écran d'une session se
/// redessine souvent (coût, CI, état…), et regrouper des centaines d'étapes à
/// chaque fois ne sert à rien. Les étapes ne sont qu'ajoutées : leur nombre et
/// l'identité de la première et de la dernière suffisent à voir un changement.
@MainActor
final class SessionJournalMemo {
    struct Journal {
        var rows: [WorkspaceText.Row] = []
        /// Le nombre d'actions (étapes « outil ») de la session.
        var actions = 0
    }

    private var count = -1
    private var firstId: UUID?
    private var lastId: UUID?
    private var cached = Journal()

    func journal(_ steps: [AgentStep]) -> Journal {
        if steps.count == count, steps.first?.id == firstId, steps.last?.id == lastId { return cached }
        count = steps.count
        firstId = steps.first?.id
        lastId = steps.last?.id
        cached = Journal(
            rows: WorkspaceText.rows(steps),
            actions: steps.reduce(0) { $0 + ($1.kind == .tool ? 1 : 0) }
        )
        return cached
    }
}
