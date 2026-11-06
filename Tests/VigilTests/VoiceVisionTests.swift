import XCTest
@testable import VigilCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class VoiceVisionTests: XCTestCase {
    func testOnlyNaturalEnglishVoicesAreOffered() {
        for id in ["com.apple.eloquence.en-GB.Rocko", "com.apple.speech.synthesis.voice.BadNews", "com.apple.speech.synthesis.voice.Bubbles", "com.apple.voice.super-compact.en-GB.Daniel"] {
            XCTAssertFalse(VoiceVisionPolicy.naturalVoice(identifier:id,language:"en-GB"))
        }
        XCTAssertTrue(VoiceVisionPolicy.naturalVoice(identifier:"com.apple.voice.enhanced.en-GB.Daniel",language:"en-GB"))
        XCTAssertTrue(VoiceVisionPolicy.naturalVoice(identifier:"com.apple.siri.natural.Arthur",language:"en-GB"))
        XCTAssertFalse(VoiceVisionPolicy.naturalVoice(identifier:"com.apple.voice.enhanced.fr-FR.Thomas",language:"fr-FR"))
    }
    func testNaturalVoiceQualityBeatsLocaleAndAlphabeticalOrder() {
        let compact = VoiceVisionPolicy.voiceRank(identifier:"com.apple.voice.compact.en-GB.Daniel",language:"en-GB",quality:1)
        let enhanced = VoiceVisionPolicy.voiceRank(identifier:"com.apple.voice.enhanced.en-US.Ava",language:"en-US",quality:2)
        let premium = VoiceVisionPolicy.voiceRank(identifier:"com.apple.voice.premium.en-GB.Daniel",language:"en-GB",quality:3)
        XCTAssertGreaterThan(enhanced,compact); XCTAssertGreaterThan(premium,enhanced)
    }
    func testContinuousRecognitionFindsNewNameAfterBackgroundSpeech() {
        XCTAssertEqual(VigilVoiceCommand.wakePhrase(in: "Some earlier conversation. Virgil, what is this?"), "virgil what is this")
        XCTAssertEqual(VigilVoiceCommand.wakePhrase(in: "Vigil hello. Vigil, look at me"), "vigil look at me")
        XCTAssertNil(VigilVoiceCommand.wakePhrase(in: "The visual design of the village"))
        XCTAssertNil(VigilVoiceCommand.wakePhrase(in: "Please tell Rachel about the meeting"))
    }
    func testPhoneticWakeOnlyAtStartAndManualCommandWindow() {
        for name in ["Vigil", "Virgil", "Vigils", "Vigel", "Vidjil", "Visual", "Rachel", "Vigill", "Vigl"] {
            XCTAssertTrue(VigilVoiceCommand.hasWakeWord(name), name)
            XCTAssertEqual(VigilVoiceCommand.parse(name + ", what is this?"), .whatIsThis(""), name)
            XCTAssertNil(VigilVoiceCommand.parse("Tell " + name + " what is this"), name)
        }
        for text in ["vigilance", "village", "vigorous", "hello rachel", "tell virgil", "rachels"] {
            XCTAssertFalse(VigilVoiceCommand.hasWakeWord(text), text)
        }
        XCTAssertEqual(VigilVoiceCommand.parse("what is this?", requiresWakeWord: false), .whatIsThis(""))
        XCTAssertNil(VigilVoiceCommand.parse("what is this?"))
        XCTAssertNil(VigilVoiceCommand.parse("Rachel what is thisish"))
    }
    func testWakeRequiresSeparateNameAndExactCommand() {
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil, what is this?"), .whatIsThis(""))
        XCTAssertEqual(VigilVoiceCommand.parse("VIGIL! Look at me: does this shirt suit me?"), .lookAtMe("does this shirt suit me"))
        for text in ["vigilance what is this", "tell Vigil look at me", "Vigil look at memory", "Vigil what is thisish", "what is this", "look at me"] {
            XCTAssertNil(VigilVoiceCommand.parse(text), text)
        }
    }
    func testSpeechAndBubbleAreShortAndNeverRawJSON() {
        XCTAssertEqual(VoiceVisionPolicy.sentence("A blue shirt. More detail!"), "A blue shirt.")
        XCTAssertEqual(VoiceVisionPolicy.sentence("{\"choice\":\"uncertain\"}"), VoiceVisionPolicy.unavailable)
        XCTAssertEqual(VoiceVisionPolicy.sentence(" \n "), VoiceVisionPolicy.unavailable)
        let long = VoiceVisionPolicy.sentence(Array(repeating: "word", count: 200).joined(separator: " "))
        XCTAssertLessThanOrEqual(long.split(separator: " ").count, 24)
        XCTAssertLessThanOrEqual(long.count, 181)
        XCTAssertEqual(VoiceVisionPolicy.volume(.nan), 0.5)
        XCTAssertEqual(VoiceVisionPolicy.volume(-1), 0)
        XCTAssertEqual(VoiceVisionPolicy.volume(100), 1)
    }
    func testVisualQuestionAcceptsNaturalAnswerAndSkipsTextOnlyModel() async throws {
        let transport = QuestionTransport()
        let text = ModelCandidate(provider: "nvidia", model: "text-only", vision: false, endpoint: "https://integrate.api.nvidia.com/v1/chat/completions")
        let vision = ModelCandidate(provider: "nvidia", model: "vision", vision: true, endpoint: text.endpoint)
        let router = ModelHealthRouter(candidates: [text, vision], keys: ["nvidia": "synthetic"], transport: transport)
        let reply = try await router.complete(ModelPrompt(text: "What is this?", image: Data([0]), purpose: .question))
        XCTAssertFalse(reply.local)
        XCTAssertEqual(reply.text, "A blue shirt.")
        let calls = await transport.calls
        XCTAssertEqual(calls, ["vision"])
    }
    func testFocusStillRequiresClassificationJSON() async throws {
        let transport = QuestionTransport()
        let vision = ModelCandidate(provider: "nvidia", model: "vision", vision: true, endpoint: "https://integrate.api.nvidia.com/v1/chat/completions")
        let router = ModelHealthRouter(candidates: [vision], keys: ["nvidia": "synthetic"], transport: transport)
        let reply = try await router.complete(ModelPrompt(text: "Task: Synthetic", image: Data([0])))
        XCTAssertTrue(reply.local)
        XCTAssertEqual(try FocusDecision.decode(Data(reply.text.utf8)), .uncertain)
    }
    func testQuestionFailureNeverPretendsToSeeOrUsesPaidOpenRouter() async throws {
        let transport = QuestionTransport()
        let paid = ModelCandidate(provider: "openrouter", model: "vendor/paid", vision: true, endpoint: "https://openrouter.ai/api/v1/chat/completions")
        let router = ModelHealthRouter(candidates: [paid], keys: ["openrouter": "synthetic"], transport: transport)
        let reply = try await router.complete(ModelPrompt(text: "What is this?", image: Data([0]), purpose: .question))
        XCTAssertTrue(reply.local)
        XCTAssertEqual(reply.text, VoiceVisionPolicy.unavailable)
        let calls = await transport.calls; XCTAssertTrue(calls.isEmpty)
    }
    func testPermissionRevocationPreventsQuestionSend() async throws {
        let transport = QuestionTransport()
        let model = ModelCandidate(provider: "nvidia", model: "vision", vision: true, endpoint: "https://integrate.api.nvidia.com/v1/chat/completions")
        let router = ModelHealthRouter(candidates: [model], keys: ["nvidia": "synthetic"], transport: transport)
        do { _ = try await router.complete(ModelPrompt(text: "synthetic", image: Data([0]), purpose: .question), permitsSend: { false }); XCTFail("Sent after revocation") }
        catch { XCTAssertEqual(error as? RouterError, .privateScreen) }
        let calls = await transport.calls; XCTAssertTrue(calls.isEmpty)
    }
    func testQuestionsNeverUseSubscriptionGoOrPaidModels() async throws {
        let transport = QuestionTransport()
        let go = ModelCandidate(provider: "opencode-go", model: "glm-free-looking", vision: true, endpoint: "https://opencode.ai/inference/go/openai/v1/chat/completions")
        let zenPaid = ModelCandidate(provider: "opencode", model: "paid", vision: true, endpoint: "https://opencode.ai/zen/v1/chat/completions")
        let free = ModelCandidate(provider: "openrouter", model: "vendor/model:free", vision: true, endpoint: "https://openrouter.ai/api/v1/chat/completions")
        let router = ModelHealthRouter(candidates: [go, zenPaid, free], keys: ["opencode-go": "synthetic", "opencode": "synthetic", "openrouter": "synthetic"], transport: transport)
        let reply = try await router.complete(ModelPrompt(text: "One step for a synthetic task", purpose: .question))
        XCTAssertEqual(reply.provider, "openrouter")
        let calls = await transport.calls; XCTAssertEqual(calls, ["vendor/model:free"])
    }
}

private actor QuestionTransport: HTTPTransport {
    var calls: [String] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        calls.append(body["model"] as! String)
        let data = Data(#"{"choices":[{"message":{"content":"A blue shirt."}}]}"#.utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
