@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AppleSpeechOutput: NSObject, VoiceAssistantSpeaking,
    AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, locale: Locale) async throws {
        let spokenText = Self.spokenText(from: text)
        guard !spokenText.isEmpty else {
            throw VoiceAssistantBackendError.speechOutput
        }

        stop()
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish(with: .failure(CancellationError()))
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finish(with: .success(()))
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(CancellationError()))
        }
    }

    private func finish(with result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func spokenText(from response: String) -> String {
        response
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(
                of: #"\[([^\]\n]+)\]\((?:[^()\n]|\([^()\n]*\))+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^[\s>*#-]+"#,
                with: "",
                options: [.regularExpression]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
