import Foundation

@MainActor
private final class FakeVoiceTranscriber: VoiceAssistantTranscribing {
    var permissions: VoiceAssistantPermissions
    var requestedPermissions: VoiceAssistantPermissions
    var transcript: String
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init(
        permissions: VoiceAssistantPermissions,
        requestedPermissions: VoiceAssistantPermissions? = nil,
        transcript: String = "What is the radius?"
    ) {
        self.permissions = permissions
        self.requestedPermissions = requestedPermissions ?? permissions
        self.transcript = transcript
    }

    func requestPermissions() async -> VoiceAssistantPermissions {
        permissions = requestedPermissions
        return requestedPermissions
    }

    func start(locale: Locale) throws {
        startCount += 1
    }

    func stopAndReturnFinalTranscript() async throws -> String {
        stopCount += 1
        return transcript
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class FakeVoiceSpeaker: VoiceAssistantSpeaking {
    private(set) var spokenText: String?
    private(set) var stopCount = 0

    func speak(_ text: String, locale: Locale) async throws {
        spokenText = text
    }

    func stop() {
        stopCount += 1
    }
}

private actor FakeVoiceResponder: VoiceAssistantResponding {
    let currentAvailability: AssistantOnDeviceAvailability
    let answer: String
    private(set) var receivedTranscript: String?
    private(set) var receivedContext: VoiceAssistantContextSnapshot?

    init(
        availability: AssistantOnDeviceAvailability = .available,
        answer: String = "The radius is the forearm bone on the thumb side."
    ) {
        currentAvailability = availability
        self.answer = answer
    }

    func availability() async -> AssistantOnDeviceAvailability {
        currentAvailability
    }

    func respond(
        to transcript: String,
        context: VoiceAssistantContextSnapshot
    ) async throws -> String {
        receivedTranscript = transcript
        receivedContext = context
        return answer
    }

    func receivedValues() -> (String?, VoiceAssistantContextSnapshot?) {
        (receivedTranscript, receivedContext)
    }
}

@main
struct VoiceAssistantContractCheck {
    static func main() async throws {
        try await runStateMachineChecks()
        try await runPermissionChecks()
        try await runControlChecks()
        try runSourceAndPrivacyChecks()
        print("Voice assistant contract checks passed.")
    }

    @MainActor
    private static func runStateMachineChecks() async throws {
        let granted = VoiceAssistantPermissions(
            microphone: .granted,
            speechRecognition: .granted
        )
        let transcriber = FakeVoiceTranscriber(permissions: granted)
        let responder = FakeVoiceResponder()
        let speaker = FakeVoiceSpeaker()
        let context = VoiceAssistantContextSnapshot(
            educationalCaseName: "Odyssey (Demo)",
            modelName: "Right Forearm VRT",
            regionName: "Right Forearm",
            laterality: "right",
            revealState: .bone,
            focusedAnnotationLabel: "Illustrative fracture marker",
            audience: .patient
        )
        let controller = VoiceAssistantController(
            transcriber: transcriber,
            responder: responder,
            speaker: speaker,
            contextProvider: StaticVoiceAssistantContextProvider(context: context),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: true),
            locale: Locale(identifier: "en-SG")
        )

        expect(
            controller.state == .unavailable(.notPrepared),
            "initial unavailable state"
        )
        await controller.prepare()
        expect(controller.state == .ready, "prepared state")

        await controller.startPressToTalk()
        expect(controller.state == .listening, "explicit listening state")
        expect(transcriber.startCount == 1, "one microphone start")

        await controller.stopPressToTalk()
        expect(controller.state == .ready, "ready after spoken answer")
        expect(transcriber.stopCount == 1, "one final transcript request")
        expect(
            speaker.spokenText == "The radius is the forearm bone on the thumb side.",
            "model answer reaches speech output"
        )
        let received = await responder.receivedValues()
        expect(received.0 == "What is the radius?", "ephemeral final transcript routing")
        expect(received.1 == context, "read-only semantic context routing")

        await controller.startPressToTalk()
        controller.cancel()
        expect(controller.state == .cancelled, "explicit cancellation state")
        expect(transcriber.cancelCount == 1, "recognition cancellation")
        expect(speaker.stopCount == 1, "speech cancellation")

        let emptyTranscriber = FakeVoiceTranscriber(
            permissions: granted,
            transcript: "   "
        )
        let emptyController = VoiceAssistantController(
            transcriber: emptyTranscriber,
            responder: FakeVoiceResponder(),
            speaker: FakeVoiceSpeaker(),
            contextProvider: StaticVoiceAssistantContextProvider(context: context),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: true)
        )
        await emptyController.prepare()
        await emptyController.startPressToTalk()
        await emptyController.stopPressToTalk()
        expect(
            emptyController.state == .failed(.emptyTranscript),
            "empty speech fails closed"
        )
    }

    @MainActor
    private static func runPermissionChecks() async throws {
        let undetermined = VoiceAssistantPermissions(
            microphone: .undetermined,
            speechRecognition: .undetermined
        )
        let granted = VoiceAssistantPermissions(
            microphone: .granted,
            speechRecognition: .granted
        )
        let transcriber = FakeVoiceTranscriber(
            permissions: undetermined,
            requestedPermissions: granted
        )
        let controller = VoiceAssistantController(
            transcriber: transcriber,
            responder: FakeVoiceResponder(),
            speaker: FakeVoiceSpeaker(),
            contextProvider: StaticVoiceAssistantContextProvider(
                context: .odysseyRightForearm
            ),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: true)
        )

        await controller.prepare()
        expect(
            controller.state == .permissionRequired(undetermined),
            "prepare does not request permission"
        )
        await controller.startPressToTalk()
        expect(
            controller.state == .listening,
            "explicit press may request permission and listen"
        )

        let denied = VoiceAssistantPermissions(
            microphone: .denied,
            speechRecognition: .granted
        )
        let deniedTranscriber = FakeVoiceTranscriber(
            permissions: undetermined,
            requestedPermissions: denied
        )
        let deniedController = VoiceAssistantController(
            transcriber: deniedTranscriber,
            responder: FakeVoiceResponder(),
            speaker: FakeVoiceSpeaker(),
            contextProvider: StaticVoiceAssistantContextProvider(
                context: .odysseyRightForearm
            ),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: true)
        )
        await deniedController.prepare()
        await deniedController.startPressToTalk()
        expect(
            deniedController.state == .permissionRequired(denied),
            "denied permission never starts capture"
        )
        expect(deniedTranscriber.startCount == 0, "no denied microphone start")
    }

    @MainActor
    private static func runControlChecks() async throws {
        let granted = VoiceAssistantPermissions(
            microphone: .granted,
            speechRecognition: .granted
        )
        let disabledController = VoiceAssistantController(
            transcriber: FakeVoiceTranscriber(permissions: granted),
            responder: FakeVoiceResponder(),
            speaker: FakeVoiceSpeaker(),
            contextProvider: StaticVoiceAssistantContextProvider(
                context: .odysseyRightForearm
            ),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: false)
        )
        await disabledController.prepare()
        expect(
            disabledController.state == .unavailable(.disabledByClinician),
            "clinician adapter disables voice"
        )
        await disabledController.startPressToTalk()
        expect(
            disabledController.state == .unavailable(.disabledByClinician),
            "disabled adapter blocks push-to-talk"
        )

        let unavailableController = VoiceAssistantController(
            transcriber: FakeVoiceTranscriber(permissions: granted),
            responder: FakeVoiceResponder(availability: .modelNotReady),
            speaker: FakeVoiceSpeaker(),
            contextProvider: StaticVoiceAssistantContextProvider(
                context: .odysseyRightForearm
            ),
            enablementProvider: StaticVoiceAssistantEnablementProvider(isEnabled: true)
        )
        await unavailableController.prepare()
        expect(
            unavailableController.state == .unavailable(
                .appleIntelligence(.modelNotReady)
            ),
            "model availability is truthful"
        )
    }

    private static func runSourceAndPrivacyChecks() throws {
        let projectDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let voiceDirectory = projectDirectory.appendingPathComponent(
            "UpperLimbPOC/MedicalAssistant"
        )
        let voiceFiles = [
            "VoiceAssistantModels.swift",
            "VoiceAssistantController.swift",
            "AppleSpeechTranscriber.swift",
            "AppleSpeechOutput.swift",
            "MedicalAssistantVoiceResponder.swift",
            "VoiceAssistantLiveFactory.swift"
        ]
        let source = try voiceFiles.map { fileName in
            try String(
                contentsOf: voiceDirectory.appendingPathComponent(fileName),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        expect(source.contains("requiresOnDeviceRecognition = true"), "local transcription")
        expect(source.contains("MedicalSafetyPolicy"), "existing safety policy reuse")
        expect(source.contains("AppleFoundationModelClient"), "existing model client reuse")
        expect(source.contains("AVSpeechSynthesizer"), "native speech output")
        expect(!source.contains("PeerSession"), "no transport coupling")
        expect(!source.contains("UserDefaults"), "no transcript persistence")
        expect(!source.contains("FileManager"), "no transcript file storage")
        expect(!source.contains("URLSession"), "no speech network client")
        expect(!source.contains("wake word"), "no always-listening implementation")

        let infoURL = projectDirectory.appendingPathComponent(
            "UpperLimbPOC/InfoVision.plist"
        )
        let info = try String(contentsOf: infoURL, encoding: .utf8)
        expect(info.contains("NSMicrophoneUsageDescription"), "microphone usage string")
        expect(info.contains("NSSpeechRecognitionUsageDescription"), "speech usage string")

        let allStates: [VoiceAssistantState] = [
            .unavailable(.notPrepared),
            .permissionRequired(VoiceAssistantPermissions(
                microphone: .undetermined,
                speechRecognition: .undetermined
            )),
            .ready,
            .listening,
            .transcribing,
            .thinking,
            .speaking,
            .cancelled,
            .failed(.transcriptionFailed)
        ]
        expect(Set(allStates.map(\.label)).count == 9, "all required UI states")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError("Voice assistant check failed: \(message)")
        }
    }
}
