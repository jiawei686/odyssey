@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class AppleSpeechTranscriber: VoiceAssistantTranscribing {
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultContinuation: CheckedContinuation<String, Error>?
    private var terminalResult: Result<String, Error>?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var hasInputTap = false
    private var isCapturing = false

    var permissions: VoiceAssistantPermissions {
        VoiceAssistantPermissions(
            microphone: Self.microphonePermission(),
            speechRecognition: Self.speechPermission()
        )
    }

    func requestPermissions() async -> VoiceAssistantPermissions {
        async let microphone = Self.requestMicrophonePermission()
        async let speech = Self.requestSpeechPermission()
        return await VoiceAssistantPermissions(
            microphone: microphone,
            speechRecognition: speech
        )
    }

    func start(locale: Locale) throws {
        guard permissions.areGranted else {
            throw VoiceAssistantBackendError.audioCapture
        }

        cancel()
        terminalResult = nil
        latestTranscript = ""

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable
        else {
            throw VoiceAssistantBackendError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw VoiceAssistantBackendError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0,
              recordingFormat.channelCount > 0
        else {
            throw VoiceAssistantBackendError.audioCapture
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: recordingFormat
        ) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true

        self.recognizer = recognizer
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.receive(result: result, error: error)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isCapturing = true
        } catch {
            cleanUpCapture()
            recognitionTask?.cancel()
            cleanUpRecognition()
            throw VoiceAssistantBackendError.audioCapture
        }
    }

    func stopAndReturnFinalTranscript() async throws -> String {
        if let terminalResult {
            self.terminalResult = nil
            return try terminalResult.get()
        }
        guard isCapturing, recognitionRequest != nil else {
            throw VoiceAssistantBackendError.audioCapture
        }

        stopAudioInput()
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            if let terminalResult {
                self.terminalResult = nil
                continuation.resume(with: terminalResult)
            } else {
                resultContinuation = continuation
                startFinalizationTimeout()
            }
        }
    }

    func cancel() {
        stopAudioInput()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        finish(with: .failure(CancellationError()))
    }

    private func receive(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString
            if result.isFinal {
                let transcript = latestTranscript.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                finish(with: transcript.isEmpty
                    ? .failure(VoiceAssistantBackendError.noSpeech)
                    : .success(transcript))
                return
            }
        }

        if error != nil {
            finish(with: .failure(VoiceAssistantBackendError.transcription))
        }
    }

    private func finish(with result: Result<String, Error>) {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        cleanUpCapture()
        cleanUpRecognition()
        if let continuation = resultContinuation {
            resultContinuation = nil
            continuation.resume(with: result)
        } else {
            terminalResult = result
        }
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isCapturing = false
        cleanUpCapture()
    }

    private func cleanUpCapture() {
        guard hasInputTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }

    private func cleanUpRecognition() {
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
    }

    private func startFinalizationTimeout() {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            let transcript = latestTranscript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            finish(with: transcript.isEmpty
                ? .failure(VoiceAssistantBackendError.noSpeech)
                : .success(transcript))
        }
    }

    private static func microphonePermission() -> VoiceAssistantPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .undetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .granted
        @unknown default:
            .denied
        }
    }

    private static func speechPermission() -> VoiceAssistantPermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            .undetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .granted
        @unknown default:
            .denied
        }
    }

    private static func requestMicrophonePermission() async
        -> VoiceAssistantPermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    private static func requestSpeechPermission() async
        -> VoiceAssistantPermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let permission: VoiceAssistantPermissionStatus = switch status {
                case .notDetermined:
                    .undetermined
                case .restricted:
                    .restricted
                case .denied:
                    .denied
                case .authorized:
                    .granted
                @unknown default:
                    .denied
                }
                continuation.resume(returning: permission)
            }
        }
    }
}
