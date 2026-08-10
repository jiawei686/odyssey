# Medical education assistant

## Purpose and boundary

`MedicalAssistant` is a spatial visionOS learning assistant for patients and
clinicians. An automatically presented USDZ avatar is its entry point, while a
separate text panel remains the accessible conversation surface. It provides general
educational information and can explain the deterministically selected anatomy
entity. It is not a medical adviser, diagnostic system, treatment tool, or
patient-specific clinical service.

The assistant receives only the region name, laterality, focused anatomy name,
conversation text, and retrieved public reference excerpts. It does not receive
world transforms, hand joints, camera frames, images, DICOM, registration
confidence, or companion payloads, and it cannot mutate overlay state.

## Runtime architecture

- `AssistantAvatarView`: volumetric USDZ scene, bounded idle rotation, and
  gaze-plus-pinch conversation-panel toggle.
- `MedicalAssistantView`: independent conversation window, streaming messages,
  voice/text composer, and settings surface.
- `AssistantVoiceController`: on-device partial speech recognition and system
  speech synthesis. Captured audio is not saved.
- `MedicalAssistantStore`: main-actor conversation and request state.
- `AppleFoundationModelClient`: visionOS 26+ streaming Foundation Models client
  with device, setting, model-readiness, and locale availability checks.
- `OpenAICompatibleClient`: isolated OpenAI-compatible streaming Chat
  Completions client.
- `AssistantCredentialStore`: device-only Keychain storage for the API key.
- `AssistantConversationRepository`: optional protected local conversation file.
- `MedicalKnowledgeRepository`: local retrieval over versioned JSON entries.
- `MedicalSafetyPolicy`: input limits, identifier blocking, urgent local response,
  system role, app-control prohibition, and citation allow-listing.

The assistant exposes two explicit providers:

```text
Default:  Apple Intelligence / Foundation Models (on-device, visionOS 26+)
Optional: GPT-5.4 Cloud (explicit user selection)
```

The cloud configuration is:

```text
Base URL: https://api.xcode.best/v1/
Model:    gpt-5.4
API:      POST /chat/completions
Mode:     streamed SSE response
```

An authenticated non-streaming Chat Completions probe returned a valid
`gpt-5.4` response on 2026-08-09. Earlier `gpt-5.6-luna` probes returned a
temporary provider service-unavailable error, so that model is not the current
default. The app presents provider errors as recoverable.

Apple Intelligence does not expose Siri or Siri's private context. The app
creates a `LanguageModelSession`, supplies the same bounded safety instructions
and retrieved excerpts used by the cloud path, and checks
`SystemLanguageModel.default.availability` plus `supportsLocale` before sending.
There is no automatic cloud fallback: changing from on-device to cloud is a
visible user choice. Simulator availability is not physical-device evidence.

## Spatial and voice interaction

1. Launch `UpperLimbPOC`; the assistant avatar opens automatically to the left
   of the anatomy library without opening the conversation panel.
2. Look at the avatar and pinch to open the conversation panel. Pinch the avatar
   again to close only the panel; the avatar stays present throughout.
3. Voice mode is selected by default but remains idle until the wearer presses
   the microphone. Partial speech recognition appears live after that explicit
   push-to-talk action; 1.3 seconds of silence submits that one utterance.
4. Provider output streams into the assistant message as it arrives. After the
   final answer, the system voice reads it aloud. Listening does not resume
   until the wearer presses the microphone again.
5. Switch to Text for keyboard input at any time. The toolbar control can hide
   both assistant scenes or restore the avatar if needed.

The avatar uses a seven-second idle cycle and turns only 14 degrees to either
side of its imported forward orientation, so it never rotates away from the
user. The animation is disabled when Reduce Motion is enabled.

Voice input requires microphone and Speech Recognition permission. Recognition
is constrained to Apple's on-device recognizer; if the current locale has no
on-device recognizer, use Text instead. Speech synthesis uses the system voice
and does not send answer audio to the model provider.

## API key setup

Apple Intelligence requires no API key. For the optional cloud provider, do not
add a key to Swift, a plist, an xcconfig file, or a shared Xcode scheme. Open
the assistant's gear menu, select GPT-5.4 Cloud, enter the key in the secure
field, and save it to the current simulator or device Keychain.

For a one-time Debug simulator launch, the app can import
`UPPER_LIMB_ASSISTANT_API_KEY` from the process environment into Keychain. Do
not commit that environment value. A distributed build must use a team-owned
backend proxy so the provider credential is never shipped in the app.

## Memory and knowledge

Recent turns are bounded before each request: the on-device path uses at most
8 messages and 6,000 characters, while the cloud path uses at most 16 messages
and 12,000 characters. Conversation persistence is off by default; a user may
enable protected local persistence and clear it at any time. API credentials
and conversation content use separate stores.

The bundled corpus includes existing Odyssey anatomy metadata and selected
public SGH AHPedia summaries with stable source URLs. Every entry is visibly
marked as pending app clinical review. The app does not crawl AskGov at runtime,
does not call its disallowed `/api/` path, and displays only source markers that
were supplied by local retrieval and reused by the model.

Assistant answers support simple Markdown paragraphs, short lists, and bold
emphasis. Model-supplied Markdown link targets are removed before rendering;
clickable source links come only from the locally retrieved citation allow-list.

## Validation

`Tools/MedicalAssistantContractCheck.swift` verifies multilingual retrieval,
identifier rejection, urgent local handling, diagnostic and renderer
boundaries, citation allow-listing, automatic avatar presentation, panel
toggling, bounded idle motion, explicit push-to-talk transcription, both provider
routes, guarded Foundation Models integration, and absence of embedded
credentials or spatial transforms. The
validation script also checks the avatar checksum, Xcode resource registration,
and privacy usage descriptions before the clean platform builds.

For a Debug simulator smoke route, launch with
`--assistant-on-device-smoke`. It attempts one generic Radius education
question without using a network request. The app detects the Vision Pro
Simulator before it calls Foundation Models and reports that a physical Vision
Pro is required. Select GPT-5.4 Cloud explicitly for simulator chat testing.
A successful physical Vision Pro response remains required evidence for the
on-device provider.

Physical Vision Pro review still needs to confirm avatar placement and scale,
real gaze-plus-pinch activation, microphone recognition, speech playback,
window comfort, accessibility, Keychain behavior, cancellation, and recovery
from provider/network failures. A named clinical reviewer must approve source
text and the adversarial prompt set before any external demonstration presents
the answers as medically reviewed.

## Future presentation layer

The current avatar has presentation-only idle rotation. It may later gain
state-specific animation and spatial speech bubbles for ready, thinking,
speaking, and warning. Text UI remains the accessible fallback. The avatar must
not receive credentials, medical memory, tracking coordinates, or authority to
manipulate anatomy.
