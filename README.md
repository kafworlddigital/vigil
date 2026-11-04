# Vigil

A calm native focus companion for Mac, iPhone and iPad. Forked from **Riley Brown’s [Bluey](https://github.com/rbrown101010/bluey-by-riley)**. The original Unlicense in `LICENSE` is retained. Bluey's conservative nudge policy and encrypted paired-device transport are adapted here; the new interface and icon belong to Vigil.

## Start
Open Vigil on the Mac and phone or iPad on the same Wi-Fi. Choose Pair on the Mac, then scan that QR in the companion. Paste an OpenRouter key into Mac Settings, or try the named Tuck import. Permission is requested when a feature is used: screen checks, on-device microphone/speech, camera pairing, and read-only calendar.

Hold the blueberry and say “focus on …” to start a session; “park this: …” saves an idea. Type and buttons work too. The Mac owns the timer. The companions show its state and keep the last daily summary for offline viewing. Only session records, settings and parked ideas cross the encrypted local link; API keys, screenshots, OCR and audio do not.

## Privacy and models
All on-screen window owners and titles are checked before capture, after capture and before a send. Unreadable normal-window metadata fails closed and skips the check. QuickTime Player, Teams, Outlook, Remote Desktop/Windows App, Chrome Remote Desktop and any QualityAI window skip the whole observation as `private (skipped)`. Screenshots and OCR are never saved. The app does not record meetings, control other apps or play speech.

Non-work screens, reduced to 1100px maximum, OCR, front app and the declared task are sent only to OpenRouter. There are no OpenAI API calls, SDKs, Realtime, Decisions, Responses or transcription services. A weekly model catalogue refresh admits explicitly zero-cost image models, with an ordered fallback chain and a zero-price provider ceiling. Invalid classification JSON is uncertain. Repeated strong fresh off-task observations are required to nudge. Nudge wording uses a free text model or the fixed sentence. An explicitly configured OpenCode Go key is used only when paid fallback is enabled. Paid OpenRouter choices are capped at $0.20/$0.80 per million input/output tokens.

The default interval is 60 seconds, adjustable 30–120. A safe 50-request daily cap is enforced across classification, retry and wording calls. A 60-second interval alone does not guarantee a full day within free quota. HTTP429 backs off; the local timer, parking lot and meeting/break reminders keep working. The running cost and actual selected model appear in Settings.

The phone also parks ideas offline, retaining their original time and stable identity until it reconnects. Ideas are saved locally first, then appended idempotently to `~/Library/Mobile Documents/com~apple~CloudDocs/Vigil/Parking Lot.md`. If iCloud is unavailable they stay queued for retry. Never edit calendar events. A ten-minute heads-up ends the focus session before the next timed meeting; after 50 uninterrupted active minutes a stretch/water suggestion appears. Focus-minute totals include confirmed on-task observations only; drift count means gentle nudges, not every ambiguous check.

## Build and verification
The project spec is `project.yml` (XcodeGen), with `Vigil` universal iOS and `VigilMac` native macOS schemes. Both compile shared Swift directly; no bundled third-party frameworks. Apple team V892V3PC6T, bundle IDs `com.kafworlddigital.vigil.ios` and `.mac`.

`swift test --jobs 2` runs parser, mocked routing/quotas, privacy, parking, timing and summary tests. The manual GitHub workflow builds Release, runs `simctl install` + `simctl launch` on both iPhone and iPad simulators, proves each process survives 15 seconds, saves simulator screenshots, and checks `otool -L` recursively for embedded @rpath dependencies. Device installation requires those proofs for the same source commit. Simulator screenshots are not physical-device acceptance.

See `docs/DELIVERY.md` for this build's actual delivery status. No schedules or collectors are created.
