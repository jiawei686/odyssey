import SwiftUI

struct MedicalAssistantView: View {
    @EnvironmentObject private var assistant: MedicalAssistantStore
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var windowCoordinator: AssistantWindowCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = AssistantVoiceController()
    @State private var isConfirmingClear = false
    @State private var didRunOnDeviceSmoke = false
    @State private var inputMode: AssistantInputMode = .voice
    @State private var lastSpokenMessageID: UUID?

    private var anatomyContext: AssistantAnatomyContext {
        AssistantAnatomyContext(overlay: overlay)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                Divider()
                conversation
                Divider()
                composer
            }
            .navigationTitle("Medical Education Assistant")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isConfirmingClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear conversation")
                    .disabled(assistant.messages.isEmpty)

                    Button {
                        assistant.isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Assistant settings")
                }
            }
        }
        .frame(minWidth: 480, minHeight: 540)
        .task {
            await assistant.prepare()
            runOnDeviceSmokeIfRequested()
            await startVoiceIfPossible()
        }
        .onAppear(perform: windowCoordinator.conversationDidAppear)
        .onDisappear {
            voice.cancelListening()
            voice.stopSpeaking()
            windowCoordinator.conversationDidDisappear()
        }
        .onChange(of: inputMode) { _, mode in
            if mode == .voice {
                Task { await startVoiceIfPossible() }
            } else {
                voice.cancelListening()
                voice.stopSpeaking()
            }
        }
        .onChange(of: voice.completedUtterance) { _, utterance in
            guard let utterance else { return }
            assistant.draft = utterance.text
            assistant.send(anatomyContext: anatomyContext)
            speakLatestResponseIfNeeded()
        }
        .onChange(of: voice.speechCompletionCount) { _, _ in
            Task { await startVoiceIfPossible() }
        }
        .onChange(of: assistant.activity) { _, activity in
            if activity == .idle {
                speakLatestResponseIfNeeded()
            } else {
                voice.cancelListening()
            }
        }
        .onChange(of: assistant.messages.last?.id) { _, _ in
            speakLatestResponseIfNeeded()
        }
        .onChange(of: assistant.isSelectedProviderAvailable) { _, _ in
            Task { await startVoiceIfPossible() }
        }
        .sheet(isPresented: $assistant.isShowingSettings) {
            MedicalAssistantSettingsView()
                .environmentObject(assistant)
        }
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear conversation", role: .destructive) {
                assistant.startNewConversation()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func runOnDeviceSmokeIfRequested() {
#if DEBUG
        guard !didRunOnDeviceSmoke,
              ProcessInfo.processInfo.arguments.contains(
                "--assistant-on-device-smoke"
              )
        else { return }
        didRunOnDeviceSmoke = true
        assistant.provider = .onDevice
        assistant.draft = "Explain the radius and its main function in plain language."
        assistant.send(anatomyContext: anatomyContext)
#endif
    }

    private func startVoiceIfPossible() async {
        guard inputMode == .voice,
              assistant.activity == .idle,
              assistant.isSelectedProviderAvailable,
              voice.errorMessage == nil,
              !voice.isListening,
              !voice.isSpeaking,
              !ProcessInfo.processInfo.arguments.contains(
                "--assistant-on-device-smoke"
              )
        else { return }
        await voice.startListening()
    }

    private func speakLatestResponseIfNeeded() {
        guard inputMode == .voice,
              assistant.activity == .idle,
              let message = assistant.messages.last,
              message.role == .assistant,
              !message.text.isEmpty,
              message.id != lastSpokenMessageID
        else { return }

        lastSpokenMessageID = message.id
        let rendered = AssistantResponseFormatter.attributedText(
            from: message.text
        )
        voice.speak(
            String(rendered.characters),
            language: speechLanguage(for: message.text)
        )
    }

    private func speechLanguage(for text: String) -> String {
        if text.unicodeScalars.contains(where: {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }) {
            return "zh-CN"
        }
        return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(
                    assistant.activity.label,
                    systemImage: assistant.activity == .waitingForResponse
                        ? "ellipsis.message.fill"
                        : "cross.case.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(
                    assistant.activity == .waitingForResponse ? .orange : .green
                )

                Spacer()

                Picker("Audience", selection: $assistant.audience) {
                    ForEach(AssistantAudience.allCases) { audience in
                        Text(audience.displayName).tag(audience)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Label(
                "Educational information only - not diagnosis or treatment",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)

            HStack(spacing: 8) {
                Label(
                    assistant.provider.displayName,
                    systemImage: assistant.provider.systemImage
                )
                    .fontWeight(.semibold)
                Spacer()
                Text(assistant.providerStatus)
                    .foregroundStyle(
                        assistant.isSelectedProviderAvailable
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.orange)
                    )
            }
            .font(.caption)

            HStack(spacing: 8) {
                Image(systemName: "view.3d")
                Text("Discussing \(overlay.focusedBoneName)")
                    .lineLimit(1)
                Text("\(anatomyContext.laterality) \(overlay.selectedRegion.name)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            if !assistant.isSelectedProviderAvailable {
                HStack {
                    Label(
                        assistant.providerStatus,
                        systemImage: assistant.provider == .cloud
                            ? "key.fill"
                            : "exclamationmark.triangle.fill"
                    )
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(
                        assistant.onDeviceAvailability == .simulatorUnsupported
                            ? "Choose provider"
                            : "Configure"
                    ) {
                        assistant.isShowingSettings = true
                    }
                    .buttonStyle(.bordered)
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if assistant.messages.isEmpty {
                        emptyConversation
                    } else {
                        ForEach(assistant.messages) { message in
                            if !message.text.isEmpty {
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }

                    if assistant.activity == .waitingForResponse {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing a grounded response")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }

                    if let errorMessage = assistant.errorMessage {
                        errorRow(errorMessage)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("conversation-bottom")
                }
                .padding(20)
            }
            .onChange(of: assistant.messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
            .onChange(of: assistant.activity) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
            .onChange(of: assistant.messages.last?.text) { _, _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }

    private var emptyConversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Start a conversation", systemImage: "message.fill")
                .font(.title3.weight(.semibold))

            suggestionButton(
                "Explain the selected structure",
                question: "Explain \(overlay.focusedBoneName) and its main function."
            )
            suggestionButton(
                "Compare radius and ulna",
                question: "Compare the radius and ulna in plain language."
            )
            suggestionButton(
                "Quiz me",
                question: "Give me a short quiz about the selected upper-limb anatomy."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func suggestionButton(_ title: String, question: String) -> some View {
        Button {
            assistant.draft = question
            assistant.send(anatomyContext: anatomyContext)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!assistant.isSelectedProviderAvailable)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            if assistant.canRetryLastRequest {
                Button("Retry", systemImage: "arrow.clockwise") {
                    assistant.retryLastRequest(anatomyContext: anatomyContext)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.callout)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Input mode", selection: $inputMode) {
                ForEach(AssistantInputMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if inputMode == .voice {
                voiceComposer
            } else {
                textComposer
            }

            Text("Do not enter names, identifiers, records, patient images, or DICOM data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var voiceComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(voice.state.label, systemImage: voice.state.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(voice.isListening ? .green : .secondary)

                    Text(voice.liveTranscript.isEmpty
                         ? voice.state.label
                         : voice.liveTranscript)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .textSelection(.enabled)
                }

                if assistant.activity == .waitingForResponse {
                    Button {
                        assistant.cancelRequest()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .help("Stop response")
                } else if voice.isSpeaking {
                    Button {
                        voice.stopSpeaking()
                        Task { await startVoiceIfPossible() }
                    } label: {
                        Image(systemName: "speaker.slash.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .help("Stop speaking")
                } else {
                    Button {
                        if voice.isListening {
                            voice.finishListening()
                        } else {
                            Task { await voice.startListening() }
                        }
                    } label: {
                        Image(systemName: voice.isListening
                              ? "waveform.circle.fill"
                              : "mic.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .disabled(!assistant.isSelectedProviderAvailable)
                    .help(voice.isListening ? "Finish question" : "Start listening")
                }
            }

            if let errorMessage = voice.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var textComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Ask a general health or anatomy question",
                text: $assistant.draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                assistant.send(anatomyContext: anatomyContext)
            }

            if assistant.activity == .waitingForResponse {
                Button {
                    assistant.cancelRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .help("Stop response")
            } else {
                Button {
                    assistant.send(anatomyContext: anatomyContext)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .disabled(
                    assistant.draft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || !assistant.isSelectedProviderAvailable
                )
                .help("Send question")
            }
        }
    }
}

private struct MessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 70) }

            VStack(alignment: .leading, spacing: 10) {
                Text(AssistantResponseFormatter.attributedText(from: message.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if message.isLocalSafetyResponse {
                    Label("Local safety response", systemImage: "shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if !message.citations.isEmpty {
                    Divider()
                    ForEach(message.citations) { citation in
                        citationView(citation)
                    }
                }
            }
            .padding(14)
            .background(
                message.role == .user
                    ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                    : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .frame(maxWidth: 520, alignment: .leading)

            if message.role == .assistant { Spacer(minLength: 70) }
        }
    }

    @ViewBuilder
    private func citationView(_ citation: AssistantCitation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let url = citation.url {
                Link(destination: url) {
                    Label(
                        "[\(citation.id)] \(citation.title)",
                        systemImage: "link"
                    )
                }
            } else {
                Label(
                    "[\(citation.id)] \(citation.title)",
                    systemImage: "doc.text"
                )
            }
            Text("\(citation.publisher) - \(citation.reviewStatus)")
                .foregroundStyle(.secondary)
            Text("Verified \(citation.lastVerified)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct MedicalAssistantSettingsView: View {
    @EnvironmentObject private var assistant: MedicalAssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Response provider", selection: $assistant.provider) {
                        ForEach(AssistantProvider.allCases) { provider in
                            Label(
                                provider.displayName,
                                systemImage: provider.systemImage
                            )
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(assistant.activity == .waitingForResponse)

                    if assistant.provider == .onDevice {
                        Label(
                            assistant.onDeviceAvailability.label,
                            systemImage: assistant.onDeviceAvailability.isAvailable
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            assistant.onDeviceAvailability.isAvailable
                                ? .green
                                : .orange
                        )

                        Button("Check availability", systemImage: "arrow.clockwise") {
                            Task {
                                await assistant.refreshOnDeviceAvailability()
                            }
                        }
                        .disabled(assistant.onDeviceAvailability == .checking)

                        Text(
                            assistant.onDeviceAvailability.configurationGuidance
                                ?? "Runs on a physical Vision Pro without an API key or network request. The current language and downloaded Apple Intelligence model must be supported."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Endpoint", value: "api.xcode.best/v1")
                        LabeledContent("Model", value: "gpt-5.4")

                        SecureField("API key", text: $apiKey)
                            .textContentType(.password)

                        HStack {
                            Label(
                                assistant.isAPIKeyConfigured
                                    ? "Key stored in Keychain"
                                    : "No key configured",
                                systemImage: assistant.isAPIKeyConfigured
                                    ? "checkmark.shield.fill"
                                    : "key.slash"
                            )
                            .foregroundStyle(
                                assistant.isAPIKeyConfigured ? .green : .orange
                            )
                            Spacer()
                            Button("Save") {
                                if assistant.saveAPIKey(apiKey) {
                                    apiKey = ""
                                    dismiss()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                        }

                        if assistant.isAPIKeyConfigured {
                            Button("Delete API key", role: .destructive) {
                                assistant.deleteAPIKey()
                                apiKey = ""
                            }
                        }

                        Text("Cloud use is explicit. The key is stored only in this device's Keychain; a team backend proxy is required before distribution.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Memory") {
                    Toggle(
                        "Remember conversations on this device",
                        isOn: Binding(
                            get: { assistant.remembersConversations },
                            set: assistant.setRemembersConversations
                        )
                    )
                    Text("Session context is always retained while the app is open. Persistent memory is optional and can be cleared from the conversation window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data boundary") {
                    Text("Use only general educational questions. Do not submit patient identifiers, records, images, scans, or DICOM data.")
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Assistant Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
