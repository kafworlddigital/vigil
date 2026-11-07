# Vigil delivery handoff — 7 November 2026

Keith: signed build13 installed; sole Release build, ordinary relaunch, existing Dock pin preserved. Settled background CPU 0.098% before → 0.198% after; baseline already low, no reduction claim. Microphone C922; playback follows current default. Internal dd-today was removed. Exact source normally pushed on features-voice-vision at 6c23a93ef5fbefb035924d112385836108d2fc6d. No further Keith build is needed.

Macy Mac: build14 archived once, signed, audited, uploaded and processed VALID. External Macy group assignment and full en-US What to Test independently read back. Beta App Review submitted, currently WAITING_FOR_REVIEW. Do not repeat the archive/upload/submission while review is waiting. No Macy app was installed on the delivery devices. The initial rejected installer and private diagnostics remain preserved; the accepted upload uses corrected profile readability/signing on the same compiled archive.

Macy iOS: the one archive attempt failed on a main-actor nudge call in DeviceLink.swift. The source is fixed and syntax/isolation checked, but there is no successful native iOS archive or build14 upload. A further native archive requires a new build allocation under the one-archive limit. Preserve the original failed-attempt guard/log/result before another attempt; do not silently remove the guard or claim native compilation passed.

From the existing private delivery folder, once a further iOS archive is authorised:

```sh
mv macy-features/ios-archive-attempt.json macy-features/ios-archive-attempt-failed-20261107.json
mv macy-features/ios-archive-result.json macy-features/ios-archive-result-failed-20261107.json
if [ -e macy-features/ios-14.xcarchive ]; then mv macy-features/ios-14.xcarchive macy-features/ios-14-failed-20261107.xcarchive; fi
python3 macy-features/archive.py ios
python3 macy-features/package_upload.py package ios
python3 macy-features/audit.py ios
python3 macy-features/package_upload.py upload ios
# After Apple processing is VALID:
python3 macy-features/submit.py ios
```

Preserve existing audit tar/receipts before an iOS audit replaces them. The archive helper checks exact source hashes, uses one compiler job/internal dd-macy and removes DerivedData. Refresh Apple versions before selecting 14 again. Never touch held external volumes, force-push, print credentials or install Macy's edition on Keith's devices. Signing/upload helpers use the existing private profiles and App Store Connect configuration; no new keys are needed.

Monitor Apple status with `python3 macy-features/apple_readback_today.py`. Build4 is APPROVED and IN_BETA_TESTING for both apps; Macy iOS membership INSTALLED, Mac INVITED. Those are Apple delivery states, not proof that the new features run on her devices.

Brain changes are deployed on the existing server, preserving newer friend-edition restrictions and existing credentials. US neural speech and an isolated real free-provider answer after two injected failures passed, using synthetic input and no device playback. Production monitoring excludes paid/subscription and stopped OpenAI/Anthropic routes. The speech model stays on the server. No keys or private records are bundled.

Validation: 54 portable core tests, 18 server tests, both platform syntax, edition isolation and diff checks pass. Mac native Release/signing/installer/exact-artifact privacy checks pass. iOS native retry, simulator and real-device acceptance remain unperformed. Private HANDOFF.md contains exact paths, receipts and the full continuation record.
