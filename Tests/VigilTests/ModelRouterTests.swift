import XCTest
@testable import VigilCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ModelRouterTests:XCTestCase {
    let go=ModelCandidate(provider:"opencode-go",model:"synthetic-go",vision:true,endpoint:"https://opencode.ai/inference/go/openai/v1/chat/completions")
    let or=ModelCandidate(provider:"openrouter",model:"synthetic:free",vision:true,endpoint:"https://openrouter.ai/api/v1/chat/completions")
    let nim=ModelCandidate(provider:"nvidia",model:"synthetic-vision",vision:true,endpoint:"https://integrate.api.nvidia.com/v1/chat/completions")
    func testFirstTwoProvidersBlockedStillGetsThirdProviderAnswer() async throws {
        let mock=HealthTransport()
        let router=ModelHealthRouter(candidates:[go,or,nim],keys:keys,transport:mock)
        await router.probeAll()
        // Control the measured ranking: a loaded runner may resume sleeping tasks in any order.
        var ranked:[ModelHealth]=[]
        for (index,candidate) in [go,or,nim].enumerated() {
            var state=ModelHealth(candidate);state.status="green";state.checkedAt=Date();state.latency=Double(index+1)/10;ranked.append(state)
        }
        await router.importHealth(ranked)
        let before=await router.snapshot();XCTAssertEqual(before.map(\.provider),["opencode-go","openrouter","nvidia"])
        await mock.fail(["opencode-go":429,"openrouter":401])
        let reply=try await router.complete(ModelPrompt(text:"Synthetic task"))
        XCTAssertEqual(reply.provider,"nvidia");XCTAssertEqual(reply.text,"Third provider answered");XCTAssertFalse(reply.local)
        let calls=await mock.calls;XCTAssertEqual(Array(calls.suffix(3)),["opencode-go","openrouter","nvidia"])
        let states=await router.snapshot()
        XCTAssertEqual(states.first{$0.provider=="opencode-go"}?.status,"amber")
        XCTAssertEqual(states.first{$0.provider=="openrouter"}?.error,"auth")
        XCTAssertEqual(states.first{$0.provider=="nvidia"}?.status,"green")
    }
    func testAllRemoteFailuresKeepTextAndValidScreenFallback() async throws {
        let mock=HealthTransport();await mock.fail(["opencode-go":503,"openrouter":503,"nvidia":503])
        let router=ModelHealthRouter(candidates:[go,or,nim],keys:keys,transport:mock)
        let text=try await router.complete(ModelPrompt(text:"Read a page"));XCTAssertTrue(text.local);XCTAssertFalse(text.text.isEmpty)
        let screen=try await router.complete(ModelPrompt(text:"Task: Review a page\nApp: Unclear",image:Data([0])))
        XCTAssertTrue(screen.local);XCTAssertEqual(try FocusDecision.decode(Data(screen.text.utf8)),.uncertain)
    }
    func testScreenNeverGoesToTextOnlyModel() async throws {
        let text=ModelCandidate(provider:"nvidia",model:"synthetic-text",vision:false,endpoint:nim.endpoint)
        let mock=HealthTransport();let router=ModelHealthRouter(candidates:[text],keys:keys,transport:mock)
        let reply=try await router.complete(ModelPrompt(text:"Synthetic",image:Data([0])))
        XCTAssertTrue(reply.local);let calls=await mock.calls;XCTAssertTrue(calls.isEmpty)
    }
    func testCooldownSurvivesRestartAndProbeResumesAfterReset() async throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:file)}
        let mock=HealthTransport();await mock.fail(["opencode-go":429]);let now=Date()
        let first=ModelHealthRouter(candidates:[go],keys:keys,transport:mock,healthURL:file)
        await first.probeAll(now:now)
        let restarted=ModelHealthRouter(candidates:[go],keys:keys,transport:mock,healthURL:file)
        await mock.fail([:]);await restarted.probeAll(now:now.addingTimeInterval(1))
        var calls=await mock.calls;XCTAssertEqual(calls.count,1)
        let saved=await restarted.snapshot();XCTAssertEqual(saved.first?.status,"amber")
        XCTAssertEqual(saved.first!.cooldownUntil!.timeIntervalSince(now),60,accuracy:1)
        await restarted.probeAll(now:now.addingTimeInterval(61))
        calls=await mock.calls;XCTAssertEqual(calls.count,2)
        let healthy=await restarted.snapshot();XCTAssertEqual(healthy.first?.status,"green")
    }
    func testBrainHealthRanksDirectFallbackAndPreservesSharedCooldown() async throws {
        let mock=HealthTransport();let router=ModelHealthRouter(candidates:[go,or,nim],keys:keys,transport:mock)
        var limited=ModelHealth(go);limited.status="amber";limited.checkedAt=Date();limited.cooldownUntil=Date().addingTimeInterval(3600)
        var healthy=ModelHealth(nim);healthy.status="green";healthy.checkedAt=Date();healthy.latency=0.1
        await router.importHealth([limited,healthy])
        let reply=try await router.complete(ModelPrompt(text:"synthetic"))
        XCTAssertEqual(reply.provider,"nvidia");let calls=await mock.calls;XCTAssertEqual(calls,["nvidia"])
        let states=await router.snapshot();XCTAssertEqual(states.first{$0.provider=="opencode-go"}?.cooldownUntil,limited.cooldownUntil)
    }
    func testNoOpenAIOrGPTOrUnknownEndpointIsPermitted() {
        for model in ["openai/o1","gpt-6","vendor/GPT-other","codex-something"] {
            XCTAssertFalse(ModelCandidate(provider:"openrouter",model:model,vision:true,endpoint:or.endpoint).permitted)
        }
        XCTAssertFalse(ModelCandidate(provider:"nvidia",model:"model",vision:true,endpoint:"https://untrusted.example/v1/chat/completions").permitted)
        XCTAssertFalse(ModelCandidate(provider:"openrouter",model:"openrouter/free",vision:true,endpoint:or.endpoint).permitted)
        XCTAssertTrue(go.permitted)
    }
    func testPrivateScreenFailsBeforeAnyProviderCall() async throws {
        let mock=HealthTransport();let router=ModelHealthRouter(candidates:[go],keys:keys,transport:mock)
        do{_=try await router.complete(ModelPrompt(text:"private",image:Data([0])),permitsSend:{false});XCTFail("Private screen sent")}
        catch{XCTAssertEqual(error as? RouterError,.privateScreen)}
        let calls=await mock.calls;XCTAssertTrue(calls.isEmpty)
    }
    func testVisionProbeActuallyIncludesSyntheticImage() async {
        let mock=HealthTransport();let router=ModelHealthRouter(candidates:[go],keys:keys,transport:mock)
        await router.probeAll();let images=await mock.imageCalls;XCTAssertEqual(images,1)
    }
    var keys:[String:String]{["opencode-go":"synthetic","openrouter":"synthetic","nvidia":"synthetic"]}
}
actor HealthTransport:HTTPTransport {
    private var failures:[String:Int]=[:]
    private(set) var calls:[String]=[]
    private(set) var imageCalls=0
    func fail(_ statuses:[String:Int]){failures=statuses}
    func data(for request:URLRequest) async throws -> (Data,HTTPURLResponse) {
        let host=request.url!.host!
        let provider=host=="opencode.ai" ? "opencode-go":host=="openrouter.ai" ? "openrouter":"nvidia"
        calls.append(provider)
        let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        let user=(body["messages"] as! [[String:Any]]).last!
        if user["content"] is [[String:Any]] {imageCalls+=1}
        let status=failures[provider] ?? 200
        if status==200 {try await Task.sleep(nanoseconds:provider=="opencode-go" ? 1_000_000:provider=="openrouter" ? 30_000_000:100_000_000)}
        let data=status==200 ? try JSONSerialization.data(withJSONObject:["choices":[["message":["content":"Third provider answered"]]]]):Data("unavailable".utf8)
        return (data,HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Retry-After":"60"])!)
    }
}
