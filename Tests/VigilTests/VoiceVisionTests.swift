import XCTest
@testable import VigilCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class VoiceVisionTests: XCTestCase {
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
