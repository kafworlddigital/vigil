# Vigil inference service

The service provides stateless model failover for the apps. It binds only to 127.0.0.1:8798, behind the dedicated HTTPS `/vigil` route. Existing server routes are preserved.

Provider keys, device-token hashes, health state and the allowed Apple app-ID map live outside the repository in `/srv/projects/vigil-private`. Never commit them. Tokens are separate for each device. There are no prompt, image, audio or conversation logs. Synthetic probes run in parallel at launch and every 30 minutes. A limited model rests until its retry time; individual live attempts have a 20-second timeout. OpenRouter is constrained to zero prices, Ollama is restricted to verified included models, and OpenAI/GPT models are rejected.

TestFlight enrolment uses Apple's signed app transaction with the official App Store Server Library and Apple trust roots. Download the root certificates from https://www.apple.com/certificateauthority/ into an `apple-roots` directory beside the service. Populate `apple-apps.json` with the actual bundle-ID to Apple app-ID mapping after creating the App Store Connect records. Do not substitute unsigned or shared enrolment secrets.

Run `python -m unittest -v test_brain` in this directory. Tests use synthetic transport and no provider keys. The first two providers fail while the third answers; other tests cover cooldown persistence, vision-only screen routing, local fallback, one-use administrative activation and rejection of unsigned enrolment.
