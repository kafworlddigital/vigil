# Vigil

A calm native focus companion for Mac, iPhone and iPad. Based on Riley Brown’s [Bluey](https://github.com/rbrown101010/bluey-by-riley); the original Unlicense is retained. Vigil keeps the original face, animator, cursor buddy, chirp and focus timeline, and adds parking, calendar, history and model failover.

## Start

The short first-launch cards explain the face, pairing, sideways phone, hold to talk, parking and privacy. Every card has Skip. Replay them from Settings. Open Pair on the Mac, then scan its QR with the phone on the same network. The Mac owns the session timer; each edition has its own data and pairing namespace.

Hold the face to speak, or type a focus task. Park an idea to keep it for later. The phone can save ideas offline and merge them when reconnected. Calendar access is read-only. Notifications start enabled in the app; the operating system still controls notification permission. Settings and the Mac menu open Help, which explains every feature and common problems. Report a problem opens an email addressed to contact@kafworlddigital.com; it does not send automatically.

The Mac has a menu bar item, an independent floating face and a persistent Dock icon. Face size and visibility are adjustable; hold Option to drag it. The original cursor buddy appears for nudges. Ordinary face clicks pass through. No automatic input occurs.

## Models and privacy

The HTTPS Contabo brain routes eligible requests through configured OpenCode Go and free OpenCode Zen, OpenRouter, NVIDIA NIM and Ollama Cloud models. Catalogues exclude OpenAI/GPT models. Screen requests use vision-capable models only. Synthetic health checks run on launch and every 30 minutes, in parallel; responding models are ranked by measured latency. Live calls use roughly 20-second model timeouts and fail over on errors. Limit responses apply a persisted cooldown, using the supplied reset time where available. Settings shows green, amber or red status dots and Test all now. A saved catalogue or key is not proof of a responding model.

When remote answers fail, supported devices can use Apple Foundation Models for text. Screen checking falls back to a conservative local heuristic. Provider availability and limits vary; no paid fallback outside the authorised Go plan is enabled.

Protected work windows skip observation. Eligible checks can send the declared task, app information, recognised screen text and a reduced image to the brain and selected provider. Screenshots and recognised text are not saved as history. Provider retention and data-use policies still apply. Audio recognition stays on-device. The brain does not log prompt/image content or keep session history. The encrypted local companion link does not transmit provider keys or raw screen captures.

## Macy edition

Separate bundle IDs `com.kafworlddigital.vigil.m.ios` and `.m.mac` both display “Vigil”. Data folders, preferences, Keychain scope and pairing discovery are separate from Keith’s edition. Verified Apple AppTransaction enrolment exchanges a valid install for a per-device brain token, with no pasted provider keys or app account. This still requires the correct App Store records and actual TestFlight acceptance; a successful unsigned build is not evidence of enrolment or TestFlight delivery. Only Keith is authorised as a tester.

## Build and release checks

`project.yml` generates the shared Swift targets with XcodeGen. Build 4 uses team V892V3PC6T. Standard public GitHub Actions macOS runners perform all builds and simulator work. The workflow runs 27 unit tests, builds both editions for Mac, iOS device and simulator, checks embedded `@rpath` dependencies and Apple silicon support, and proves 15-second Mac, iPhone and iPad simulator launches. Six server tests cover routing, cooldowns, vision filtering and invalid enrolment. The first-two-providers-blocked test must still return an answer from the third.

Before installation, the signed staged Mac app also needs its real Mac launch, cursor, animation and human screenshot checks. Cloud cursor images are labelled renderer fixtures. Simulator recovery can reuse a successful build job only after verifying that the application sources are unchanged; compile and UI-proof commits are recorded separately.

Icon v2 is rendered from the native character: black background, whole face and crown, 70% body width, purple-blue glow and clear margins. The iOS master is opaque RGB. Rounded-mask previews at 1024, 180, 60 and 40 pixels and actual simulator home/Dock images are inspected before installation. Physical-device, simulator and cloud screenshots remain distinctly labelled.

See [delivery status](docs/DELIVERY.md) for the exact source, successful run and installations. Secrets, device records and private screenshots are not committed. Recovery volumes are never needed for this project.
