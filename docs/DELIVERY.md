# Vigil 1.0 · build 2 verification

Application source: `5f23cfdab1054537ecb48e41ae5398395418b77a`.

[Successful hosted verification](https://github.com/kafworlddigital/vigil/actions/runs/41767559387) completed on 4 November 2026:

- 18 unit tests passed, zero failures: strict classification parsing, free/explicit-cheap routing with mocked HTTP, quota/cooldown, weekly catalogue refresh, any-visible-window privacy including unreadable metadata, idempotent parking and failure preservation, nudge/break/meeting timing, daily summary, encrypted authenticated loopback, tamper and replay rejection.
- Both iPhone and iPad Release apps were installed with `xcrun simctl install`, launched with `xcrun simctl launch`, and independently found running after 15 seconds. Simulator screenshots and launch receipts were saved by the workflow.
- Native macOS and universal iOS device Release builds succeeded. Recursive `otool -L` inspection found no missing embedded `@rpath` dependencies. Shared Swift compiles directly into each target, with system frameworks only.
- All compilation and simulator work ran on hosted macOS. No local Mac build, clone, DerivedData or build archive was used. The code workspace is on the existing owner-controlled cloud server.

Build 2 additionally cancels microphone use on cancelled holds and inactive scenes, and creates the audio engine only for an intentional hold. Original Bluey licensing and attribution are retained. No other application bundle is replaced by the new identifiers.

The screenshots above are simulator evidence. Physical-device installation and UI receipts remain private; they are separate from simulator launch proof. Pairing, on-device speech, calendar permission and authenticated screen classification require owner first-use setup and their own runtime acceptance. The network tests use synthetic data and mocked responses. No real work screenshot, calendar contents, API key or device pairing credential is included in the repository or hosted test inputs.

Vigil supports a named Tuck Keychain import and a secure manual paste field. Provider availability, free quota and current model pricing are checked at runtime; a catalogue entry is not proof of a successful authenticated model request. Paid fallback is off by default. No App Store or TestFlight release is performed by this workflow.
