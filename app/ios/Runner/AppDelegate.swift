import BackgroundTasks
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexoraBackground") {
      NexoraBackground.register(with: registrar)
    }
  }
}

/// Garde NEXORA en vie en arrière-plan le temps qu'une session d'agent ou une
/// réponse se termine.
///
/// - iOS 26 et plus (iOS 27 compris) : une tâche « continue » (BGContinuedProcessingTask), lancée par
///   l'utilisateur, avec sa progression dans l'interface du système ; elle dure tant
///   que le travail avance.
/// - Avant iOS 26 : le délai accordé par iOS (environ 30 secondes) ; au retour dans
///   l'app, les sessions reprennent.
class NexoraBackground: NSObject, FlutterPlugin {
  private var legacyTask: UIBackgroundTaskIdentifier = .invalid
  private var continued: AnyObject?
  private var running = false
  private var title = "NEXORA travaille…"
  private var text = ""
  private var done: Int64 = 0
  private var total: Int64 = 0

  /// Ce qui se passe, pour le diagnostic affiché dans l'app.
  private var mode = "idle"
  private var lastError: String?

  /// Le battement : iOS arrête une tâche continue qui n'avance plus, or l'agent peut
  /// attendre la réponse du modèle une minute. On fait avancer la progression toutes
  /// les 2 s tant que le travail continue.
  private var ticker: Timer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nexora/background", binaryMessenger: registrar.messenger())
    let instance = NexoraBackground()
    registrar.addMethodCallDelegate(instance, channel: channel)
    let center = NotificationCenter.default
    center.addObserver(
      instance, selector: #selector(NexoraBackground.didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      instance, selector: #selector(NexoraBackground.didBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  /// À chaque sortie de l'app pendant le travail : du temps en arrière-plan, même si
  /// celui de la sortie précédente est épuisé.
  @objc private func didEnterBackground() {
    guard running else { return }
    beginLegacy()
  }

  /// De retour dans l'app pendant le travail : si iOS avait arrêté la tâche continue,
  /// on en redemande une (elle doit être demandée app ouverte).
  @objc private func didBecomeActive() {
    guard running else { return }
    if #available(iOS 26.0, *) {
      if continued == nil { submitContinued() }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    // Seuls start et update changent le travail en cours (pas status ni notify).
    if call.method == "start" || call.method == "update" {
      title = args["title"] as? String ?? title
      text = args["text"] as? String ?? text
      done = Int64(args["done"] as? Int ?? 0)
      total = Int64(args["total"] as? Int ?? 0)
    }
    switch call.method {
    case "start":
      start()
      result(true)
    case "update":
      update()
      result(true)
    case "stop":
      stop()
      result(true)
    case "notify":
      notify(
        title: args["title"] as? String ?? "NEXORA",
        body: args["text"] as? String ?? "")
      result(true)
    case "status":
      result(["mode": mode, "error": lastError ?? ""])
    default:
      result(FlutterMethodNotImplemented)
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
    ticker?.invalidate()
    ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.update()
    }
  }

  private func update() {
    if #available(iOS 26.0, *) {
      if let task = continued as? BGContinuedProcessingTask { report(task) }
    }
  }

  private func stop() {
    running = false
    ticker?.invalidate()
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

  private func beginLegacy() {
    guard legacyTask == .invalid else { return }
    legacyTask = UIApplication.shared.beginBackgroundTask(withName: "NEXORA") { [weak self] in
      self?.endLegacy()
    }
  }

  private func endLegacy() {
    guard legacyTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(legacyTask)
    legacyTask = .invalid
  }

  @available(iOS 26.0, *)
  private func submitContinued() {
    let base = Bundle.main.bundleIdentifier ?? "com.maxlestage.nexora"
    // Un identifiant unique par tâche, enregistré juste avant l'envoi.
    let id = "\(base).work.\(Int(Date().timeIntervalSince1970 * 1000))"
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) {
      [weak self] task in
      guard let task = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      DispatchQueue.main.async { self?.attach(task) }
    }
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
      lastError = "\(error.localizedDescription)"
      NSLog("NEXORA : tâche de fond refusée : \(error)")
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
    task.expirationHandler = { [weak self] in
      task.setTaskCompleted(success: false)
      DispatchQueue.main.async {
        self?.continued = nil
        self?.mode = "expired"
        self?.lastError = "iOS a arrêté la tâche de fond"
      }
    }
    report(task)
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

  private func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }
}
