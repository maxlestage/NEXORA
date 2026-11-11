import BackgroundTasks
import Foundation
import NexoraKit
import UIKit
import UserNotifications

/// Garde NEXORA en vie en arrière-plan le temps qu'une session d'agent (ou une
/// réponse) se termine, et prévient par une notification quand le travail finit
/// app cachée (`services/background_work.dart` et le greffon iOS de l'app Flutter).
///
/// - iOS 26 et plus : une tâche « continue » (`BGContinuedProcessingTask`), lancée
///   par l'utilisateur, avec sa progression dans l'interface du système ; elle dure
///   tant que le travail avance.
/// - Avant iOS 26 : le délai accordé par iOS (environ 30 secondes) ; au retour dans
///   l'app, les sessions reprennent.
///
/// Il faut dans Info.plist : `BGTaskSchedulerPermittedIdentifiers` =
/// `$(PRODUCT_BUNDLE_IDENTIFIER).work.*` et `UIBackgroundModes` = `processing`.
@MainActor
final class BackgroundWork: BackgroundPlatform {
    static let shared = BackgroundWork()

    /// Les travaux en cours (la logique, dans NexoraKit).
    let jobs = BackgroundJobs()

    private var legacyTask: UIBackgroundTaskIdentifier = .invalid
    /// La tâche continue en cours (`BGContinuedProcessingTask`, iOS 26 et plus).
    private var continued: AnyObject?
    private var running = false
    private var title = "NEXORA travaille…"
    private var text = ""
    private var done: Int64 = 0
    private var total: Int64 = 0

    /// Ce qui se passe, pour le diagnostic affiché dans l'app.
    private var mode = "idle"
    private var lastError: String?

    /// Le battement : iOS arrête une tâche continue qui n'avance plus, or l'agent
    /// peut attendre la réponse du modèle une minute. La progression avance toutes
    /// les 2 s tant que le travail continue.
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        jobs.platform = self
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
            using: Self.onMain { $0.didEnterBackground() }
        ))
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main,
            using: Self.onMain { $0.didBecomeActive() }
        ))
    }

    /// Un rappel du système (sur la file principale) qui agit sur l'instance.
    private nonisolated static func onMain(_ f: @escaping @MainActor @Sendable (BackgroundWork) -> Void) -> @Sendable (Notification) -> Void {
        { _ in
            MainActor.assumeIsolated { f(BackgroundWork.shared) }
        }
    }

    // MARK: - BackgroundPlatform

    var isForeground: Bool { UIApplication.shared.applicationState == .active }

    func perform(_ call: BackgroundCall) {
        switch call {
        case let .start(t, x, d, n):
            set(t, x, d, n)
            start()
        case let .update(t, x, d, n):
            set(t, x, d, n)
            update()
        case .stop:
            stop()
        case let .notify(t, x):
            notify(title: t, body: x)
        }
    }

    func status() -> BackgroundStatus? {
        BackgroundStatus(mode: mode, error: lastError ?? "")
    }

    private func set(_ t: String, _ x: String, _ d: Int, _ n: Int) {
        title = t
        text = x
        done = Int64(d)
        total = Int64(n)
    }

    // MARK: - Cycle de vie

    /// À chaque sortie de l'app pendant le travail : du temps en arrière-plan, même
    /// si celui de la sortie précédente est épuisé.
    private func didEnterBackground() {
        guard running else { return }
        beginLegacy()
    }

    /// De retour dans l'app pendant le travail : si iOS avait arrêté la tâche
    /// continue, on en redemande une (elle doit être demandée app ouverte).
    private func didBecomeActive() {
        guard running else { return }
        if #available(iOS 26.0, *) {
            if continued == nil { submitContinued() }
        }
    }

    private func start() {
        running = true
        lastError = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        beginLegacy()
        mode = "legacy"
        if #available(iOS 26.0, *) {
            if continued == nil { submitContinued() }
        } else {
            lastError = "iOS 26 ou plus requis pour continuer longtemps en arrière-plan"
        }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.update()
            }
        }
    }

    private func update() {
        if #available(iOS 26.0, *) {
            if let task = continued as? BGContinuedProcessingTask { report(task) }
        }
    }

    private func stop() {
        running = false
        ticker?.cancel()
        ticker = nil
        mode = "idle"
        if #available(iOS 26.0, *) {
            if let task = continued as? BGContinuedProcessingTask {
                task.progress.completedUnitCount = task.progress.totalUnitCount
                task.setTaskCompleted(success: true)
            }
        }
        continued = nil
        endLegacy()
    }

    // MARK: - Délai accordé par iOS (~30 s)

    private func beginLegacy() {
        guard legacyTask == .invalid else { return }
        legacyTask = UIApplication.shared.beginBackgroundTask(withName: "NEXORA", expirationHandler: Self.expired)
    }

    /// Le délai est épuisé : la tâche est rendue (sinon iOS arrête l'app).
    private nonisolated static func expired() {
        MainActor.assumeIsolated { BackgroundWork.shared.endLegacy() }
    }

    private func endLegacy() {
        guard legacyTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(legacyTask)
        legacyTask = .invalid
    }

    // MARK: - Tâche continue (iOS 26 et plus)

    /// Une tâche du système, passée d'un fil à l'autre.
    private struct TaskBox: @unchecked Sendable {
        let task: BGTask
    }

    @available(iOS 26.0, *)
    private func submitContinued() {
        let base = Bundle.main.bundleIdentifier ?? "com.maxlestage.nexora"
        // Un identifiant unique par tâche, enregistré juste avant l'envoi.
        let id = "\(base).work.\(Int(Date().timeIntervalSince1970 * 1000))"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main, launchHandler: Self.launched)
        guard registered else {
            lastError = "identifiant de tâche non autorisé (\(id))"
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: text)
        // Si iOS ne peut pas la lancer tout de suite, il la lance dès que possible.
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            mode = "submitted"
        } catch {
            lastError = error.localizedDescription
            NSLog("NEXORA : tâche de fond refusée : \(error)")
        }
    }

    /// iOS lance la tâche (sur la file principale, demandée à l'enregistrement).
    private nonisolated static func launched(_ task: BGTask) {
        let box = TaskBox(task: task)
        MainActor.assumeIsolated {
            guard #available(iOS 26.0, *), let t = box.task as? BGContinuedProcessingTask else {
                box.task.setTaskCompleted(success: false)
                return
            }
            BackgroundWork.shared.attach(t)
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        guard running else {
            task.setTaskCompleted(success: true)
            return
        }
        continued = task
        mode = "continued"
        task.expirationHandler = Self.expiration(TaskBox(task: task))
        report(task)
    }

    /// iOS arrête la tâche continue : elle est rendue, la session reprendra au
    /// retour dans l'app.
    private nonisolated static func expiration(_ box: TaskBox) -> @Sendable () -> Void {
        {
            box.task.setTaskCompleted(success: false)
            Task { @MainActor in
                let w = BackgroundWork.shared
                w.continued = nil
                w.mode = "expired"
                w.lastError = "iOS a arrêté la tâche de fond"
            }
        }
    }

    /// La progression : sans progrès, iOS peut arrêter la tâche.
    @available(iOS 26.0, *)
    private func report(_ task: BGContinuedProcessingTask) {
        task.updateTitle(title, subtitle: text)
        // 10 000 unités : un petit pas à chaque battement, sans jamais atteindre la fin.
        task.progress.totalUnitCount = 10_000
        let real = total > 0 ? min(9_900, done * 9_900 / total) : 0
        let nudged = min(9_990, task.progress.completedUnitCount + 1)
        task.progress.completedUnitCount = max(real, nudged)
    }

    // MARK: - Notification

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
