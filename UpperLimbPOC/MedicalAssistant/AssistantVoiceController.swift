import AVFAudio
import Foundation
import Speech

enum AssistantVoiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required for voice input."
        case .speechRecognitionDenied:
            "Speech Recognition access is required for voice input."
        case .recognizerUnavailable:
            "Speech recognition is temporarily unavailable for the current language."
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is unavailable for the current language. Use text input instead."
        case .audioInputUnavailable:
            "No usable microphone input is available."
        }
    }
}

enum AssistantVoiceState: Equatable {
    case idle
    case requestingPermission
    case listening
    case speaking

    var label: String {
        switch self {
        case .idle:
            "Voice ready"
        case .requestingPermission:
            "Requesting access"
        case .listening:
            "Listening"
        case .speaking:
            "Speaking"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "mic"
        case .requestingPermission:
            "ellipsis"
        case .listening:
            "waveform"
        case .speaking:
            "speaker.wave.2.fill"
        }
    }
}

struct AssistantVoiceUtterance: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class AssistantVoiceController: NSObject, ObservableObject {
    @Published private(set) var state: AssistantVoiceState = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var completedUtterance: AssistantVoiceUtterance?
    @Published private(set) var speechCompletionCount = 0
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var hasInputTap = false

    var isListening: Bool { state == .listening }
    var isSpeaking: Bool { state == .speaking }

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func startListening(locale: Locale = .current) async {
        guard state == .idle else { return }
        errorMessage = nil
        liveTranscript = ""
        state = .requestingPermission

        do {
            guard await requestMicrophonePermission() else {
                throw AssistantVoiceError.microphoneDenied
            }
            guard state == .requestingPermission else { return }
            guard await requestSpeechPermission() == .authorized else {
                throw AssistantVoiceError.speechRecognitionDenied
            }
            guard state == .requestingPermission else { return }
            try startAudioRecognition(locale: locale)
        } catch {
            stopRecognition()
            state = .idle
            errorMessage = error.localizedDescription
        }
    }

    func finishListening() {
        deliverCurrentUtterance()
    }

    func cancelListening() {
        stopRecognition()
        liveTranscript = ""
        if state != .speaking { state = .idle }
    }

    func speak(_ rawText: String, language: String? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        cancelListening()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        if let language,
           let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        utterance.rate = 0.48
        state = .speaking
        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        guard speechSynthesizer.isSpeaking else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func startAudioRecognition(locale: Locale) throws {
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            throw AssistantVoiceError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AssistantVoiceError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AssistantVoiceError.audioInputUnavailable
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInputTap = true

        self.recognizer = recognizer
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor in
                self?.receive(result: result, error: error)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening
    }

    private func receive(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        guard state == .listening else { return }

        if let result {
            liveTranscript = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            scheduleSilenceCompletion()
            if result.isFinal {
                deliverCurrentUtterance()
                return
            }
        }

        if let error {
            stopRecognition()
            state = .idle
            if liveTranscript.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleSilenceCompletion() {
        guard !liveTranscript.isEmpty else { return }
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            self?.deliverCurrentUtterance()
        }
    }

    private func deliverCurrentUtterance() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecognition()
        state = .idle
        guard !text.isEmpty else { return }
        completedUtterance = AssistantVoiceUtterance(text: text)
        liveTranscript = ""
    }

    private func stopRecognition() {
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
    }
}

extension AssistantVoiceController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard state == .speaking else { return }
            state = .idle
            speechCompletionCount += 1
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self, state == .speaking else { return }
            state = .idle
        }
    }
}
