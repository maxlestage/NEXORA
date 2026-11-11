import AVFoundation
import Foundation
import NexoraKit
import Observation
import Speech

/// La voix de NEXORA (`services/voice.dart`) : la dictée (reconnaissance vocale de
/// l'iPhone) et la lecture à voix haute des réponses, phrase par phrase, pendant
/// qu'elles s'écrivent. Gratuit, rapide, et valable avec n'importe quel modèle.
@MainActor
@Observable
final class SpeechService: NSObject {
    /// La langue des deux côtés.
    @ObservationIgnored var locale = "fr-FR"
    /// Vitesse de lecture, de 0,3 à 0,7 (0,5 : normale).
    @ObservationIgnored var rate = 0.5

    private(set) var listening = false
    /// Ce qui a été entendu jusqu'ici.
    private(set) var transcript = ""
    /// Le niveau du son (pour animer le micro), de 0 à 1.
    private(set) var level: Double = 0
    private(set) var speaking = false
    /// La dernière erreur (micro refusé, pas de reconnaissance…).
    var error: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onPartial: ((String) -> Void)?
    @ObservationIgnored private var onFinal: ((String) -> Void)?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var limit: Task<Void, Never>?
    /// Les phrases envoyées à la synthèse et pas encore lues.
    @ObservationIgnored private var pending: Set<ObjectIdentifier> = []
    @ObservationIgnored private var onQueueDone: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Texte lu

    /// Le texte à lire, sans Markdown ni blocs de code.
    static func clean(_ text: String) -> String { SpeechText.clean(text) }

    /// Lit les phrases terminées d'une réponse en cours depuis `from` (tout le reste
    /// si `all`) ; rend la nouvelle position.
    func speakNew(_ text: String, from: Int, all: Bool) -> Int {
        guard let next = SpeechText.next(text, spoken: from, all: all) else { return from }
        for sentence in next.sentences { enqueue(sentence) }
        return next.end
    }

    // MARK: - Lecture à voix haute

    /// Ajoute du texte à lire (il est lu à la suite de ce qui est en cours).
    /// `onDone` est appelé quand tout a été lu.
    func enqueue(_ text: String, onDone: (() -> Void)? = nil) {
        if let onDone { onQueueDone = onDone }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            if pending.isEmpty { finishQueue() }
            return
        }
        prepareAudio()
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: locale)
        u.rate = Float(min(max(rate, 0.3), 0.7))
        pending.insert(ObjectIdentifier(u))
        speaking = true
        synthesizer.speak(u)
    }

    /// Lit tout un texte (Markdown nettoyé).
    func speak(_ markdown: String, onDone: (() -> Void)? = nil) {
        stopSpeaking()
        for s in SpeechText.sentences(SpeechText.clean(markdown)) { enqueue(s) }
        if let onDone {
            if pending.isEmpty { onDone() } else { onQueueDone = onDone }
        }
    }

    func stopSpeaking() {
        onQueueDone = nil
        pending.removeAll()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speaking = false
    }

    private func finished(_ id: ObjectIdentifier) {
        guard pending.remove(id) != nil, pending.isEmpty else { return }
        finishQueue()
    }

    private func finishQueue() {
        speaking = false
        let done = onQueueDone
        onQueueDone = nil
        done?()
    }

    /// Haut-parleur (pas l'écouteur), casques Bluetooth et AirPlay ; baisse le son
    /// des autres apps.
    private func prepareAudio() {
        guard !listening else { return }
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay, .duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Dictée

    /// Bascule la dictée, sans rappel (le texte entendu est dans `transcript`).
    func toggleListening() {
        if listening { stopListening() } else { listen(onPartial: { _ in }, onFinal: { _ in }) }
    }

    func startListening() { listen(onPartial: { _ in }, onFinal: { _ in }) }

    /// Écoute jusqu'à un silence de 3 secondes (2 minutes au plus). `onPartial`
    /// reçoit le texte au fur et à mesure, `onFinal` le texte complet à la fin.
    func listen(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        stopSpeaking()
        error = nil
        transcript = ""
        self.onPartial = onPartial
        self.onFinal = onFinal
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = "Reconnaissance vocale indisponible : autorisez le micro et la reconnaissance vocale dans les réglages du téléphone."
                    return
                }
                AVAudioApplication.requestRecordPermission { @Sendable granted in
                    Task { @MainActor in
                        if granted {
                            self.beginRecognition()
                        } else {
                            self.error = "Reconnaissance vocale indisponible : autorisez le micro et la reconnaissance vocale dans les réglages du téléphone."
                        }
                    }
                }
            }
        }
    }

    private func beginRecognition() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            error = "La dictée n'est pas disponible pour le moment."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            req.taskHint = .dictation
            request = req
            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tapBlock(req) { level in
                Task { @MainActor [weak self] in
                    if self?.listening == true { self?.level = level }
                }
            })
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            waitForSilence()
            limit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                self?.stopListening()
            }
            task = recognizer.recognitionTask(with: req) { @Sendable result, err in
                let text = result?.bestTranscription.formattedString
                let final = (result?.isFinal ?? false) || err != nil
                Task { @MainActor [weak self] in
                    guard let self, self.listening else { return }
                    if let text {
                        self.transcript = text
                        self.onPartial?(text)
                        self.waitForSilence()
                    }
                    if final { self.stopListening() }
                }
            }
        } catch {
            self.error = error.localizedDescription
            cancelListening()
        }
    }

    /// Trois secondes sans nouveau mot : la dictée s'arrête et le texte part.
    private func waitForSilence() {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.stopListening()
        }
    }

    /// Le micro appelle ce bloc sur son propre fil : il ne doit pas être lié à
    /// l'acteur principal.
    nonisolated private static func tapBlock(
        _ req: SFSpeechAudioBufferRecognitionRequest, level: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            req.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(n))
            level(min(max(Double(rms) * 8, 0), 1))
        }
    }

    private func endAudio() {
        silence?.cancel()
        limit?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        level = 0
    }

    /// Arrête d'écouter ; le texte entendu est envoyé (`onFinal`).
    func stopListening() {
        guard listening else { return }
        endAudio()
        let f = onFinal
        onFinal = nil
        onPartial = nil
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty { f?(heard) }
    }

    /// Arrête d'écouter sans rien envoyer.
    func cancelListening() {
        onFinal = nil
        onPartial = nil
        if listening { endAudio() }
        listening = false
        level = 0
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}
