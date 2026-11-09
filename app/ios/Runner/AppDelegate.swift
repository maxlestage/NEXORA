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

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nexora/background", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NexoraBackground(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    title = args["title"] as? String ?? title
    text = args["text"] as? String ?? text
    done = Int64(args["done"] as? Int ?? 0)
    total = Int64(args["total"] as? Int ?? 0)
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
      notify(title: title, body: text)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start() {
    running = true
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    beginLegacy()
    if #available(iOS 26.0, *) {
      if continued == nil { submitContinued() }
    }
  }

  private func update() {
    if #available(iOS 26.0, *) {
      if let task = continued as? BGContinuedProcessingTask { report(task) }
    }
  }

  private func stop() {
    running = false
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
    guard registered else { return }
    let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: text)
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
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
    task.expirationHandler = { [weak self] in
      task.setTaskCompleted(success: false)
      DispatchQueue.main.async { self?.continued = nil }
    }
    report(task)
  }

  /// La progression : sans progrès, iOS peut arrêter la tâche.
  @available(iOS 26.0, *)
  private func report(_ task: BGContinuedProcessingTask) {
    task.updateTitle(title, subtitle: text)
    task.progress.totalUnitCount = 100
    let percent: Int64
    if total > 0 {
      percent = min(99, done * 100 / total)
    } else {
      // Durée inconnue (une réponse) : on avance doucement sans jamais finir.
      percent = min(99, task.progress.completedUnitCount + 1)
    }
    task.progress.completedUnitCount = max(task.progress.completedUnitCount, percent)
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
