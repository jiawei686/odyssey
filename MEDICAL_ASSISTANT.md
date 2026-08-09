# Medical education assistant

## Purpose and boundary

`MedicalAssistant` is a text-first visionOS learning assistant for patients and
clinicians. It provides general educational information and can explain the
deterministically selected anatomy entity. It is not a medical adviser,
diagnostic system, treatment tool, or patient-specific clinical service.

The assistant receives only the region name, laterality, focused anatomy name,
conversation text, and retrieved public reference excerpts. It does not receive
world transforms, hand joints, camera frames, images, DICOM, registration
confidence, or companion payloads, and it cannot mutate overlay state.

## Runtime architecture

- `MedicalAssistantView`: independent visionOS window and settings surface.
- `MedicalAssistantStore`: main-actor conversation and request state.
- `AppleFoundationModelClient`: visionOS 26+ on-device Foundation Models client
  with device, setting, model-readiness, and locale availability checks.
- `OpenAICompatibleClient`: isolated OpenAI-compatible Chat Completions client.
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
identifier rejection, urgent local handling, diagnostic and renderer boundaries,
citation allow-listing, guarded Foundation Models integration, explicit provider
routing, and absence of embedded credentials or spatial transforms. It runs
from `Tools/validate.sh` before the clean platform builds.

For a Debug simulator smoke route, launch with
`--assistant-on-device-smoke`. It attempts one generic Radius education
question without using a network request. The app detects the Vision Pro
Simulator before it calls Foundation Models and reports that a physical Vision
Pro is required. Select GPT-5.4 Cloud explicitly for simulator chat testing.
A successful physical Vision Pro response remains required evidence for the
on-device provider.

Physical Vision Pro review still needs to confirm window placement, text entry,
comfort, accessibility, Keychain behavior, cancellation, and recovery from
provider/network failures. A named clinical reviewer must approve source text
and the adversarial prompt set before any external demonstration presents the
answers as medically reviewed.

## Future presentation layer

A later avatar or spatial speech bubble may consume only presentation states
such as ready, thinking, speaking, and warning. Text UI remains the accessible
fallback. The avatar must not receive credentials, medical memory, tracking
coordinates, or authority to manipulate anatomy.
