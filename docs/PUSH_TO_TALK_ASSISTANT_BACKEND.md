# Push-to-talk assistant backend

## Scope

This isolated reference slice adds a mockable, platform-native voice path for
the visionOS educational assistant:

`explicit press → on-device Apple Speech transcript → existing medical safety
policy and Foundation Models client → AVSpeechSynthesizer`

It does not add a wake word, background listening, a clinician UI, anatomy
controls, tracking access, `PeerSession` coupling, or persistent audio and
transcript storage. It is educational FAQ and app-navigation support only. It
must not diagnose, recommend treatment, interpret patient-specific findings,
or imply that the generic CT-derived model represents the wearer.

## Integration boundary

Create the controller with `VoiceAssistantLiveFactory.makeController(...)` and
provide two small adapters:

- `VoiceAssistantContextProviding` supplies the demo case label, selected
  model, reveal state, focused annotation label, and audience.
- `VoiceAssistantEnablementProviding` supplies the clinician-controlled
  enabled state without importing the cross-device session into this module.

The UI starts recording only by awaiting `startPressToTalk()` from an explicit
press or pinch and ends it by awaiting `stopPressToTalk()` on release. It may
bind directly to `VoiceAssistantController.state`. Cancellation calls
`cancel()`. The required states are unavailable, permission required, ready,
listening, transcribing, thinking, speaking, cancelled, and failed.

## Privacy and safety

- Speech recognition requires `requiresOnDeviceRecognition = true`.
- The audio engine is stopped and its input tap removed after every exchange.
- The final transcript is passed in memory to a single model request and is not
  exposed as persisted controller state.
- The responder reuses `MedicalSafetyPolicy`, local knowledge retrieval, and
  `AppleFoundationModelClient`; it never selects the cloud provider.
- Emergency phrases continue to receive the existing local response, while
  identifiers are rejected before model generation.
- Only semantic educational context crosses the adapter boundary. No camera
  pixels, DICOM, gaze, hand transforms, or world transforms are accepted.

## Evidence and open gate

- `[AUTO]` Fake recognizer, model, speech output, context, and enablement
  adapters cover the deterministic state transitions and fail-closed paths.
- `[BUILD]` The visionOS simulator and unsigned device-SDK targets compile, and
  the iOS companion remains isolated from the voice files.
- `[BLOCKED] DEVICE-PENDING / NOT VERIFIED` A physical Vision Pro must still
  verify microphone permission, on-device locale support, transcript quality,
  response latency, interruption/cancellation, spoken output, comfort, and the
  Apple Intelligence model-availability states.

The backend is intentionally not connected to a presentation view in this
reference branch. An upstream teammate implementation must be fetched and
audited before selecting or integrating any part of this fallback.
