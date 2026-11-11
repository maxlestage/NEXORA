import Foundation

// # Le travail en arrière-plan (port de `app/lib/services/background_work.dart`)
//
// Garde l'app en vie en arrière-plan tant qu'une session d'agent ou une réponse
// est en cours (tâche de fond sur iPhone), et prévient par une notification quand
// le travail se termine app cachée. La logique (travaux en cours, regroupement,
// cadence des mises à jour) est ici ; ce que fait le système (BGTaskScheduler,
// `beginBackgroundTask`, notifications) est dans l'app (`BackgroundWork`).

/// Ce qu'on demande au système.
public enum BackgroundCall: Sendable, Equatable {
    /// Le travail commence : titre, texte, fait, total.
    case start(title: String, text: String, done: Int, total: Int)
    /// Le travail avance.
    case update(title: String, text: String, done: Int, total: Int)
    /// Plus rien en cours.
    case stop
    /// Une notification (travail fini, app cachée).
    case notify(title: String, text: String)

    /// Le nom de la méthode dans l'app Flutter (`start`, `update`, `stop`, `notify`).
    public var method: String {
        switch self {
        case .start: "start"
        case .update: "update"
        case .stop: "stop"
        case .notify: "notify"
        }
    }

    /// Le titre transmis (vide pour `stop`).
    public var title: String {
        switch self {
        case let .start(t, _, _, _), let .update(t, _, _, _), let .notify(t, _): t
        case .stop: ""
        }
    }
}

/// Ce que fait le système, pour le diagnostic : `continued` (iOS suit la tâche),
/// `submitted`, `legacy` (~30 s seulement), `expired`, `idle`.
public struct BackgroundStatus: Sendable, Equatable {
    public let mode: String
    public let error: String

    public init(mode: String, error: String = "") {
        self.mode = mode
        self.error = error
    }

    /// Le texte et le ton du diagnostic affiché pendant le travail
    /// (`ui/widgets/background_status.dart`) ; `nil` : rien à afficher.
    public var note: (text: String, tone: Tone, symbol: String)? {
        switch mode {
        case "continued": ("Continue en arrière-plan : iOS suit la tâche.", .good, "checkmark.circle")
        case "service": ("Continue en arrière-plan (notification Android).", .good, "checkmark.circle")
        case "submitted": ("Arrière-plan demandé à iOS…", .warn, "hourglass")
        case "expired": ("iOS a arrêté la tâche de fond : la session reprend quand vous revenez.", .warn, "pause.circle")
        case "legacy": ("Arrière-plan court (~30 s)\(error.isEmpty ? "" : " : \(error)").", .warn, "timer")
        default: nil
        }
    }

    public enum Tone: Sendable { case good, warn }
}

/// Le système : il exécute les demandes, dit si l'app est au premier plan, et ce
/// qu'il fait de la tâche de fond.
@MainActor
public protocol BackgroundPlatform: AnyObject {
    func perform(_ call: BackgroundCall)
    /// L'app est affichée (pas de notification à la fin d'un travail).
    var isForeground: Bool { get }
    func status() -> BackgroundStatus?
}

/// Les travaux en cours, et leur reflet dans le système.
@MainActor
public final class BackgroundJobs {
    /// Un travail : titre, texte, fait, total.
    struct Job {
        var title: String
        var text: String
        var done: Int
        var total: Int
    }

    public weak var platform: (any BackgroundPlatform)?
    private var order: [String] = []
    private var jobs: [String: Job] = [:]
    public private(set) var active = false
    private var timer: Task<Void, Never>?
    private var ticks = 0
    /// Les mises à jour, au plus une fois par…
    public var throttle: Duration = .seconds(1)

    public init(platform: (any BackgroundPlatform)? = nil) {
        self.platform = platform
    }

    /// Un travail commence ou avance.
    public func hold(_ key: String, title: String, text: String = "", done: Int = 0, total: Int = 0) {
        let isNew = jobs[key] == nil
        if isNew { order.append(key) }
        jobs[key] = Job(title: title, text: text, done: done, total: total)
        ticks += 1
        // Démarrage tout de suite ; mises à jour au plus une fois par seconde.
        if isNew && !active {
            sync()
        } else if timer == nil {
            let pause = throttle
            timer = Task { [weak self] in
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled, let self else { return }
                self.timer = nil
                self.sync()
            }
        }
    }

    /// Un travail est fini. `doneTitle` : notification si l'app est en arrière-plan.
    public func release(_ key: String, doneTitle: String? = nil, doneText: String = "") {
        guard jobs.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
        if let doneTitle, !(platform?.isForeground ?? true) {
            platform?.perform(.notify(title: doneTitle, text: doneText))
        }
        timer?.cancel()
        timer = nil
        sync()
    }

    /// Le nombre de travaux en cours.
    public var count: Int { jobs.count }

    func sync() {
        if jobs.isEmpty {
            if active {
                active = false
                platform?.perform(.stop)
            }
            return
        }
        let job: Job
        if jobs.count == 1, let first = order.first, let j = jobs[first] {
            job = j
        } else {
            job = Job(
                title: "NEXORA · \(jobs.count) travaux en cours",
                text: order.compactMap { jobs[$0]?.title }.joined(separator: " · "),
                done: 0, total: 0
            )
        }
        // Durée inconnue : le compteur sert de progression (iOS l'exige).
        let done = job.total > 0 ? job.done : ticks
        let call: BackgroundCall = active
            ? .update(title: job.title, text: job.text, done: done, total: job.total)
            : .start(title: job.title, text: job.text, done: done, total: job.total)
        active = true
        platform?.perform(call)
    }

    /// Ce que fait le système (diagnostic).
    public func status() -> BackgroundStatus? { platform?.status() }
}
