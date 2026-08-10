import Foundation

@MainActor
enum VoiceAssistantLiveFactory {
    static func makeController(
        contextProvider: any VoiceAssistantContextProviding =
            StaticVoiceAssistantContextProvider(
                context: .odysseyRightForearm
            ),
        enablementProvider: any VoiceAssistantEnablementProviding =
            StaticVoiceAssistantEnablementProvider(isEnabled: true),
        locale: Locale = .current
    ) -> VoiceAssistantController {
        VoiceAssistantController(
            transcriber: AppleSpeechTranscriber(),
            responder: MedicalAssistantVoiceResponder(),
            speaker: AppleSpeechOutput(),
            contextProvider: contextProvider,
            enablementProvider: enablementProvider,
            locale: locale
        )
    }
}
