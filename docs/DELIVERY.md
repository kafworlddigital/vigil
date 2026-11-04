# Vigil build 3 delivery — device retries in progress

Verified application source: `e6849f99b3adf97fc2ec7f51bc9774e78664721f`. Successful cloud run: https://github.com/kafworlddigital/vigil/actions/runs/41805466041.

All 19 unit tests passed. Mac, iOS device and simulator Release builds and framework checks passed. Fresh iPhone and iPad simulators installed and launched Release, independently retained their processes for 15 seconds, and produced differing one-second animation frames.

The signed app separately passed the real-Mac gate before installation: actual scripted cursor movement, opposite gaze directions, differing one-second frames, a live cursor buddy/bubble and manual visual inspection. These are own live rendered views. Cloud Mac eye images are explicitly renderer fixtures; simulator and fixture images are not physical-device acceptance.

Mac: installed in /Applications/Vigil.app, build 3, strict signature and binary readback verified, post-install process survived 15 seconds. Previous accepted app preserved privately.

iPhone: installed version 1.0 build 3; independent native inventory confirms build 3. Physical launch is locked, so physical UI, pairing and voice are unverified.

iPad: currently unreachable. A bounded install loop is retrying at ten-minute intervals until approximately 11:36 UTC on 4 November 2026. This is pending, not successful delivery. No permanent schedule was created.

OpenRouter answered synthetic free vision and text tests; the signed Mac app's actual Test connection also answered with dots-studio/dots-3-note-preview:free. OpenCode's actual app test and official CLI report the free-usage-limit error. No paid fallback was enabled to make a test pass. Keys and private screen content were not used in public CI.

The Contabo brain move remains gated behind the incomplete second stage, as ordered. No brain service or private access route has been deployed; NVIDIA NIM and Ollama Cloud integration has not been started. The apps retain the existing direct provider/local data path.

The original Bluey character renderer, animator, shape/crown/palette, cursor engine/art/trails/bubbles, chirp and timeline/detail views were restored directly from upstream. The independent Mac face, size/visibility/Option-drag controls and Test connection are included; Vigil parking lot, calendar, history and free models remain. See CHARACTER.md for provenance.

The Desktop icon preview is 1024px, rendered from the actual upstream face and checked at 60px. The Desktop guide has eight plain lines. Private receipts and actual device images are not published. Held recovery volumes were not accessed or repaired.
