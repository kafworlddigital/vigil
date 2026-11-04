# Vigil build 4 — release checks in progress

No build 4 installation has taken place. Keith’s accepted Mac installation remains build 3; the last independently verified iPhone installation was build 3. The physical iPad installation is not yet verified. No new device retry window has started.

Application builds: commit `51396a329f7ecdc394ee67e18d876d99239e8464`, [build run 41849797194](https://github.com/kafworlddigital/vigil/actions/runs/41849797194). Its build job passed all 27 tests, all six Release builds, both 15-second Mac launches, Apple silicon checks and framework inspection. The complete workflow did not pass: simulator process checks timed out. The finished apps are preserved in its `Vigil-build` artifact.

The current UI-only recovery harness is commit `72f9c0c4352a9b5f07ed52e71d3a54f37474c884`. It verifies the successful build job and unchanged application source before reusing those apps. It opens the real Simulator window and retains the install, same-process 15-second survival, animation, screenshot and human review gates. [Native ARM recovery](https://github.com/kafworlddigital/vigil/actions/runs/41857643168) and [Intel recovery](https://github.com/kafworlddigital/vigil/actions/runs/41857651508) are pending. No pending or failed run is release approval.

Icon v2 has been generated in the app builds with a whole 70%-width face, black margins and purple-blue glow. The iOS master is opaque RGB. Native rounded-mask previews exist at 1024, 180, 60 and 40 pixels. Final home-screen and Dock review, real Mac acceptance, installation and the source asset readback remain required.

The stateless HTTPS brain is deployed on Contabo and answered from outside Tailscale. The last authenticated synthetic health snapshot confirmed 15 responding models: NVIDIA 6, Ollama Cloud 5 and OpenRouter 4. The saved Go key was rejected; Zen reported limits/access errors. These are time-specific results, not a promise of continuing availability. The real failover check injected errors for the first two providers and received an actual answer from the third in 0.832 seconds. Six server tests also passed.

The six skippable intro cards, Settings replay, version/build, model dots, Test all now, Help and email-composition link are implemented. Macy’s targets use separate bundle IDs, storage, iCloud parking files, preferences, Keychain scope and pairing discovery; both display “Vigil”. Her model enrolment requires the actual Apple app records and verified StoreKit transaction. That TestFlight enrolment has not yet been accepted on a physical device.

Macy’s TestFlight upload is pending Apple app-record setup. No testers or external groups have been added and no build has been uploaded. Only Keith is authorised as a tester. The ready-for-check Desktop note has not been created. Credentials, device inventories, private screenshots and private provider receipts are kept outside this public repository. Held recovery volumes have not been accessed.
