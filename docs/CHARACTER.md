# Character restoration

Source: Riley Brown, https://github.com/rbrown101010/bluey-by-riley, upstream commit 3f273636e3b51b29f21791d495c86e3345f168b0. The original LICENSE is preserved.

Original files restored:
- iOS/Sources/FaceView.swift: spring animator and Canvas renderer, now shared by phone and Mac.
- iOS/Sources/BlobShape.swift: blueberry outline, crown, skin gradient, colour/font helpers.
- Mac/Sources/GooglyMac/CursorOverlay.swift: original Teardrop art, bezier flights, motion, eyes, comet/string trails, bubble layout and animation.
- iOS/Sources/FocusViews.swift: FocusSummary, FocusCheckList, FocusCheckDetail and FocusTimeline.
- iOS/Sources/LiveVoice.swift: original chirp synthesis, isolated from the removed Realtime/OpenAI transport.

Small adapters connect those components to Vigil's existing encrypted transport, on-device speech, free-model classifier, settings, calendar, parking lot and history. The Mac adds an independent borderless face, whole-desktop gaze sampling, optional size/visibility, deliberate Option-drag movement and click-through at rest. Added surprise expression and blueberry glow adapt the original art; the character is not redrawn as a replacement mascot.

Before restoration, the upstream README and all nine named preview assets were reviewed. Upstream's latest README says no glow, whereas some older previews show glow; Keith explicitly requested glow, so the native original art has a soft blue halo added.

Private delivery receipts retain the exact provider results, source SHA, cloud run, real-Mac cursor/animation evidence and per-device install outcomes. Physical screenshots and credentials are never published here. A Test connection result proves only that specific synthetic request; saved keys or a model catalogue alone do not prove an answered model call.
