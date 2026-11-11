import AVFoundation
import Foundation
import Observation
import Speech

/// La voix : lecture des réponses à voix haute (phrase par phrase, pendant la
/// réponse) et dictée des messages.
@MainActor
@Observable
final class SpeechService: NSObject {
    private(set) var listening = false
    private(set) var transcript = ""
    var error: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    // MARK: - Lecture

    /// Le texte à lire, sans Markdown ni blocs de code.
    static func clean(_ text: String) -> String {
        var t = text
        while let r = t.range(of: "```[\\s\\S]*?```", options: .regularExpression) {
            t.replaceSubrange(r, with: " (bloc de code) ")
        }
        for pattern in ["`", "\\*\\*", "__", "^#+\\s*", "^\\s*[-*]\\s+", "\\[([^\\]]+)\\]\\([^)]+\\)"] {
            t = t.replacingOccurrences(of: pattern, with: pattern.hasPrefix("\\[") ? "$1" : "", options: .regularExpression)
        }
        return t
    }

    /// Lit les phrases terminées depuis `from` ; rend la nouvelle position.
    func speakNew(_ text: String, from: Int, all: Bool) -> Int {
        let clean = Self.clean(text)
        guard clean.count > from else { return from }
        var end = clean.count
        if !all {
            guard let last = clean.lastIndex(where: { ".!?…\n".contains($0) }) else { return from }
            end = clean.distance(from: clean.startIndex, to: last) + 1
            if end <= from { return from }
        }
        let start = clean.index(clean.startIndex, offsetBy: from)
        let stop = clean.index(clean.startIndex, offsetBy: end)
        let chunk = clean[start..<stop].trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty { speak(chunk) }
        return end
    }

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier == "fr" ? "fr-FR" : nil)
        synthesizer.speak(u)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var speaking: Bool { synthesizer.isSpeaking }

    // MARK: - Dictée

    func toggleListening() {
        if listening { stopListening() } else { startListening() }
    }

    func startListening() {
        error = nil
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = "Autorisez la reconnaissance vocale dans Réglages → NEXORA."
                    return
                }
                AVAudioApplication.requestRecordPermission { @Sendable granted in
                    Task { @MainActor in
                        if granted { self.beginRecognition() } else { self.error = "Autorisez le micro dans Réglages → NEXORA." }
                    }
                }
            }
        }
    }

    private func beginRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            error = "La dictée n'est pas disponible pour le moment."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tapBlock(req))
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            task = recognizer.recognitionTask(with: req) { @Sendable result, err in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor in
                    if let text { self.transcript = text }
                    if err != nil || final { self.stopListening() }
                }
            }
        } catch {
            self.error = error.localizedDescription
            stopListening()
        }
    }

    /// Le micro appelle ce bloc sur son propre fil : il ne doit pas être lié à
    /// l'acteur principal.
    nonisolated private static func tapBlock(_ req: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in req.append(buffer) }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
}
