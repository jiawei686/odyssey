import Foundation

@main
struct MedicalAssistantContractCheck {
    static func main() throws {
        let projectDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let knowledgeURL = projectDirectory.appendingPathComponent(
            "UpperLimbPOC/MedicalAssistant/Resources/MedicalAssistantKnowledge.json"
        )
        let repository = try MedicalKnowledgeRepository(
            data: Data(contentsOf: knowledgeURL)
        )
        expect(repository.entryCount >= 7, "versioned knowledge entries")
        expect(AssistantProvider.onDevice.rawValue == "onDevice", "on-device provider identity")
        expect(AssistantProvider.cloud.rawValue == "cloud", "cloud provider identity")
        expect(
            AssistantOnDeviceAvailability.simulatorUnsupported
                .userFacingMessage.contains("Simulator"),
            "simulator guidance"
        )

        let context = AssistantAnatomyContext(
            regionName: "Right Forearm & Hand",
            laterality: "right",
            focusedStructure: "Radius",
            educationalSource: "Bundled generic model"
        )
        let chineseResults = repository.retrieve(
            query: "请解释桡骨和前臂的关系",
            anatomyContext: context
        )
        expect(
            chineseResults.first?.citation.title.contains("Radius") == true,
            "Chinese anatomy retrieval"
        )
        expect(chineseResults.first?.citation.id == "S1", "stable source marker")

        let policy = MedicalSafetyPolicy()
        switch policy.evaluate("My NRIC is S1234567D") {
        case .reject:
            break
        default:
            fatalError("Medical assistant check failed: NRIC must be rejected")
        }
        switch policy.evaluate("我现在剧烈胸痛，无法呼吸") {
        case let .localResponse(message):
            expect(message.contains("995"), "local emergency response")
        default:
            fatalError("Medical assistant check failed: urgent input must stay local")
        }

        let prompt = policy.systemPrompt(
            audience: .clinician,
            anatomyContext: context,
            knowledge: chineseResults
        )
        expect(prompt.contains("Do not diagnose"), "diagnostic boundary")
        expect(prompt.contains("cannot select or move bones"), "renderer boundary")
        expect(prompt.contains("Clinician"), "audience mode")
        expect(prompt.contains("Do not include Markdown links"), "response format boundary")

        let sanitizedResponse = AssistantResponseFormatter.sanitizedMarkdown(
            "The **radius** is important. [Unapproved](https://example.com). "
                + "Approved citation [S1]. <https://example.org>"
        )
        expect(sanitizedResponse.contains("**radius**"), "safe emphasis preserved")
        expect(sanitizedResponse.contains("Unapproved"), "link label preserved")
        expect(!sanitizedResponse.contains("](https://"), "model link removed")
        expect(sanitizedResponse.contains("[S1]"), "source marker preserved")
        expect(!sanitizedResponse.contains("<https://"), "autolink removed")
        let renderedResponse = AssistantResponseFormatter.attributedText(
            from: sanitizedResponse
        )
        expect(
            String(renderedResponse.characters).contains("radius"),
            "Markdown response renders"
        )
        expect(
            !sanitizedResponse.contains("](https://")
                && !sanitizedResponse.contains("<https://"),
            "model-supplied interactive link syntax is removed"
        )

        let citations = policy.citedSources(
            in: "The radius is on the thumb side [S1]. A made-up source [S9].",
            from: chineseResults
        )
        expect(citations.count == 1, "citation allow-list")
        expect(citations[0].id == "S1", "citation identity")

        let assistantDirectory = projectDirectory.appendingPathComponent(
            "UpperLimbPOC/MedicalAssistant"
        )
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: assistantDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let combinedSource = try sourceFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
        }.joined(separator: "\n")
        expect(
            combinedSource.range(
                of: #"sk-[A-Za-z0-9]{20,}"#,
                options: .regularExpression
            ) == nil,
            "no embedded API key"
        )
        expect(
            !combinedSource.contains("worldTransform")
                && !combinedSource.contains("handTransform"),
            "no spatial transforms in assistant module"
        )
        expect(
            combinedSource.contains("SystemLanguageModel.default")
                && combinedSource.contains("#available(visionOS 26.0")
                && combinedSource.contains("supportsLocale"),
            "guarded Apple Intelligence integration"
        )
        expect(
            combinedSource.contains("case .onDevice")
                && combinedSource.contains("case .cloud"),
            "explicit provider routing"
        )
        expect(
            combinedSource.contains("SFSpeechRecognizer")
                && combinedSource.contains("requiresOnDeviceRecognition = true")
                && combinedSource.contains("AVAudioEngine")
                && combinedSource.contains("AVSpeechSynthesizer"),
            "on-device live transcription and spoken replies"
        )
        expect(
            combinedSource.contains("completeStreaming")
                && combinedSource.contains("streamResponse")
                && combinedSource.contains("session.bytes"),
            "streaming on-device and cloud responses"
        )

        let avatarURL = assistantDirectory.appendingPathComponent(
            "Resources/assistant-avatar.usdz"
        )
        let avatarValues = try avatarURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        expect(avatarValues.isRegularFile == true, "avatar USDZ resource")
        expect((avatarValues.fileSize ?? 0) > 1_000_000, "non-empty avatar model")

        let avatarSource = try String(
            contentsOf: assistantDirectory.appendingPathComponent(
                "AssistantAvatarView.swift"
            ),
            encoding: .utf8
        )
        expect(
            avatarSource.contains("targetedToAnyEntity")
                && avatarSource.contains("openWindow(")
                && avatarSource.contains("dismissWindow(id: \"MedicalAssistant\")")
                && avatarSource.contains("toggleConversation()"),
            "gaze-and-pinch conversation toggle"
        )
        expect(
            avatarSource.contains("SceneEvents.Update.self")
                && avatarSource.contains("maximumIdleYawDegrees: Float = 14")
                && avatarSource.contains("idleOscillationDuration: TimeInterval = 7")
                && avatarSource.contains("baseOrientation * idleRotation")
                && avatarSource.contains("guard !reduceMotion else { return }")
                && avatarSource.contains(".onChange(of: reduceMotion)"),
            "bounded accessible avatar idle rotation"
        )
        guard let addIndex = avatarSource.range(
            of: "content.add(avatar)"
        )?.lowerBound,
        let normalizeIndex = avatarSource.range(
            of: "normalize(avatar)"
        )?.lowerBound else {
            fatalError("Medical assistant check failed: avatar scene normalization")
        }
        expect(
            addIndex < normalizeIndex
                && avatarSource.contains("Bundle.main.url(")
                && avatarSource.contains("visualBounds(relativeTo: nil)"),
            "bundle-backed scene-coordinate avatar normalization"
        )

        let appSource = try String(
            contentsOf: projectDirectory.appendingPathComponent(
                "UpperLimbPOC/UpperLimbPOCApp.swift"
            ),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: projectDirectory.appendingPathComponent(
                "UpperLimbPOC/ContentView.swift"
            ),
            encoding: .utf8
        )
        expect(
            appSource.contains("WindowGroup(id: \"MedicalAssistantAvatar\")")
                && appSource.contains(".windowStyle(.volumetric)")
                && appSource.contains(
                    "restorationBehavior(assistantSceneRestorationBehavior)"
                )
                && appSource.contains("return .disabled")
                && appSource.contains("WindowPlacement(.leading(library))")
                && appSource.contains("WindowPlacement(.trailing(library))"),
            "non-restoring volumetric assistant scenes"
        )
        expect(
            contentSource.contains("presentAssistantAvatarIfNeeded()")
                && contentSource.contains(
                    "assistantWindow.claimAutomaticAvatarPresentation()"
                )
                && contentSource.contains(
                    "openWindow(id: \"MedicalAssistantAvatar\")"
                ),
            "automatic assistant-avatar entry flow"
        )

        let viewSource = try String(
            contentsOf: assistantDirectory.appendingPathComponent(
                "MedicalAssistantView.swift"
            ),
            encoding: .utf8
        )
        expect(
            viewSource.contains("inputMode: AssistantInputMode = .voice")
                && viewSource.contains("voice.liveTranscript")
                && viewSource.contains("assistant.messages.last?.text"),
            "voice-default live conversation UI"
        )
        expect(
            viewSource.contains("Task { await voice.startListening() }")
                && viewSource.contains("Push the microphone to start.")
                && !viewSource.contains("startVoiceIfPossible")
                && !viewSource.contains("onChange(of: voice.speechCompletionCount)"),
            "voice starts only from explicit push-to-talk and never auto-resumes"
        )

        print("Medical assistant contract checks passed.")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError("Medical assistant check failed: \(message)")
        }
    }
}
