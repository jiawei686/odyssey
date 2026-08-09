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
            !renderedResponse.runs.contains { $0.link != nil },
            "model links are not interactive"
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
