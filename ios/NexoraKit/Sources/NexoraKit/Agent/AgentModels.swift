import Foundation

/// Un dépôt sur lequel l'agent travaille.
public struct RepoTarget: Sendable, Hashable, Codable {
    public let owner: String
    public let name: String
    public let branch: String

    public init(_ owner: String, _ name: String, _ branch: String) {
        self.owner = owner
        self.name = name
        self.branch = branch
    }

    public var fullName: String { "\(owner)/\(name)" }

    enum CodingKeys: String, CodingKey {
        case owner = "o", name = "n", branch = "b"
    }

    /// Le format enregistré (même JSON que l'app Flutter).
    public func toJSON() -> [String: Any] { ["o": owner, "n": name, "b": branch] }

    public static func fromJSON(_ j: [String: Any]) -> RepoTarget? {
        guard let o = j["o"] as? String, let n = j["n"] as? String, let b = j["b"] as? String else { return nil }
        return RepoTarget(o, n, b)
    }
}

/// Où en sont les tests GitHub d'un dépôt après un envoi.
public enum CiState: String, Sendable {
    case waiting, running, passed, failed, none
}

/// Les tests GitHub d'un commit envoyé.
public struct CiReport: Sendable, Hashable {
    public let sha: String
    public var state: CiState
    public var runs: [CheckRun]

    public init(_ sha: String, state: CiState = .waiting, runs: [CheckRun] = []) {
        self.sha = sha
        self.state = state
        self.runs = runs
    }

    public var label: String {
        switch state {
        case .waiting: "Tests GitHub : en attente…"
        case .running: "Tests GitHub : en cours (\(runs.filter(\.done).count)/\(runs.count))…"
        case .passed: "Tests GitHub réussis ✅ (\(runs.count))"
        case .failed: "Tests GitHub échoués ❌ : \(runs.filter(\.failed).map(\.name).joined(separator: ", "))"
        case .none: "Aucun test automatique sur GitHub pour ce dépôt"
        }
    }
}

/// Ce qu'a donné la fusion des pull requests vertes.
public struct MergeOutcome: Sendable {
    /// Une branche a été mise à jour avec la principale : la CI doit repasser.
    public var updated = false
    /// Un vrai conflit, préparé pour l'agent (son rapport).
    public var conflict: String?
    /// Des refus de GitHub (règles de la branche…).
    public var blocked: [String] = []

    public init() {}
}

/// Le résultat de l'envoi sur un dépôt : un commit (sha) ou une pull request (url).
public struct ShipResult: Sendable, Hashable {
    public let repo: RepoTarget
    public let result: String

    public init(_ repo: RepoTarget, _ result: String) {
        self.repo = repo
        self.result = result
    }

    public var isPull: Bool { result.hasPrefix("http") }
}
