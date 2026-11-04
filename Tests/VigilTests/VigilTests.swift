import XCTest
@testable import VigilCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class VigilTests:XCTestCase {
    func testStrictClassifierAndMalformedUncertainty() throws {
        let good=Data(#"{"choice":"off_task","p_on":0.01,"p_off":0.98,"p_uncertain":0.01}"#.utf8)
        XCTAssertEqual(try FocusDecision.decode(good).activity,.offTask)
        let invalid=["{}",#"{"choice":"off_task","p_on":0,"p_off":0.1,"p_uncertain":0.9}"#,
            #"{"choice":"off_task","p_on":0,"p_off":2,"p_uncertain":-1}"#,
            #"{"choice":"off_task","p_on":true,"p_off":0,"p_uncertain":0}"#,
            #"{"choice":"off_task","p_on":0,"p_off":1,"p_uncertain":0,"explanation":"x"}"#,
            "```json\n{}\n```", "not JSON"]
        for text in invalid { XCTAssertEqual(FocusDecision.parseOrUncertain(Data(text.utf8)),.uncertain,text) }
        let on=Data(#"{"choice":"on_task","p_on":1,"p_off":0,"p_uncertain":0}"#.utf8)
        XCTAssertEqual(try FocusDecision.decode(on).activity,.onTask)
    }
    func testNudgeNeedsFreshConsecutiveEvidenceAndCooldown() {
        var policy=FocusNudgePolicy(maximumGap:90)
        func off(_ t:Double)->FocusCheck { FocusCheck(elapsed:t,activity:.offTask,probability:0.98,confidence:0.98) }
        XCTAssertFalse(policy.observe(off(60),age:1));XCTAssertFalse(policy.observe(off(120),age:1))
        XCTAssertTrue(policy.observe(off(180),age:1))
        XCTAssertFalse(policy.observe(off(240),age:1))
        XCTAssertFalse(policy.observe(FocusCheck(elapsed:300,activity:.privateSkipped),age:0))
        XCTAssertFalse(policy.observe(off(360),age:1));XCTAssertFalse(policy.observe(off(420),age:21))
        XCTAssertFalse(policy.observe(off(480),age:1));XCTAssertFalse(policy.observe(off(600),age:1))
    }
    func testCadenceAndSessionBounds() {
        var s=FocusSession(task:"Review tomorrow's agenda")
        XCTAssertEqual(s.checkInterval,60);s.configuredInterval=1;XCTAssertEqual(s.checkInterval,30)
        s.configuredInterval=200;XCTAssertEqual(s.checkInterval,120)
        s.advance(20);s.pause("Break");s.advance(100);XCTAssertEqual(s.elapsed,20)
        s.resume();s.advance(10);XCTAssertEqual(s.elapsed,30)
    }
    func testPrivacyChecksAnyVisibleWorkWindow() {
        let names=["QuickTime Player","Microsoft Teams","Microsoft Outlook","Microsoft Remote Desktop","Chrome Remote Desktop","Windows App"]
        for app in names { XCTAssertTrue(PrivacyGuard.isPrivate([VisibleWindow(owner:"Safari"),VisibleWindow(owner:app)]),app) }
        XCTAssertTrue(PrivacyGuard.isPrivate([VisibleWindow(owner:"Chrome",title:"QualityAI account notes")]))
        XCTAssertTrue(PrivacyGuard.isPrivate([VisibleWindow(owner:"Chrome",title:"Chrome Remote Desktop")]))
        XCTAssertTrue(PrivacyGuard.isPrivate([VisibleWindow(owner:"Teams",bundleID:"com.microsoft.teams2")]))
        XCTAssertFalse(PrivacyGuard.isPrivate([VisibleWindow(owner:"TextEdit",title:"Personal errands")]))
        XCTAssertTrue(PrivacyGuard.isPrivate([VisibleWindow(owner:"Chrome",readable:false)]))
    }
    func testParkingAppendPreservesExistingAndDeduplicatesRetry() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let file=dir.appendingPathComponent("Parking Lot.md")
        try Data("My existing ideas\n".utf8).write(to:file)
        let writer=ParkingLotWriter(url:file),idea=ParkedIdea(text:"A little idea\nwith a second line",createdAt:Date(timeIntervalSince1970:0))
        try writer.append(idea);try writer.append(idea)
        let text=try String(contentsOf:file)
        XCTAssertTrue(text.hasPrefix("My existing ideas\n"));XCTAssertEqual(text.components(separatedBy:idea.id.uuidString).count,2)
        XCTAssertTrue(text.contains("1970-01-01T00:00:00Z"));XCTAssertTrue(text.contains("A little idea with a second line"))
    }
    func testParkingFailureDoesNotDestroyExistingContent() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let bad=dir.appendingPathComponent("a-file")
        try Data("keep".utf8).write(to:bad)
        XCTAssertThrowsError(try ParkingLotWriter(url:bad.appendingPathComponent("Parking Lot.md")).append(ParkedIdea(text:"x")))
        XCTAssertEqual(try String(contentsOf:bad),"keep")
    }
    func testBreakAndMeetingAreOnceAndPauseResetsContinuity() {
        var timing=FocusMilestones()
        XCTAssertFalse(timing.advance(2999));XCTAssertTrue(timing.advance(1));XCTAssertFalse(timing.advance(1))
        timing.resetContinuity();XCTAssertFalse(timing.advance(2999))
        let now=Date();XCTAssertFalse(timing.meetingDue(id:"m",start:now.addingTimeInterval(601),now:now))
        XCTAssertTrue(timing.meetingDue(id:"m",start:now.addingTimeInterval(600),now:now))
        XCTAssertFalse(timing.meetingDue(id:"m",start:now.addingTimeInterval(500),now:now))
    }
    func testDailySummaryExcludesSkippedUncertainAndOtherDays() {
        let now=Date();var session=FocusSession(task:"Focus");session.startedAt=now
        session.checks=[FocusCheck(elapsed:0,activity:.onTask,sampleDuration:60),FocusCheck(elapsed:0,activity:.privateSkipped,sampleDuration:120),FocusCheck(elapsed:0,activity:.uncertain,sampleDuration:60)]
        var off=FocusCheck(elapsed:0,activity:.offTask,sampleDuration:60);off.nudged=true;session.checks.append(off)
        let summary=DailySummary(sessions:[session],ideas:[ParkedIdea(text:"today",createdAt:now),ParkedIdea(text:"old",createdAt:now.addingTimeInterval(-86400))],now:now)
        XCTAssertEqual(summary.focusMinutes,1);XCTAssertEqual(summary.driftCount,1);XCTAssertEqual(summary.parkedCount,1)
    }
    func testOnlyVerifiedZeroCostVisionModels() throws {
        let models=try RouterModel.parse(Self.catalog)
        XCTAssertEqual(models.filter{$0.free && $0.vision}.map(\.id),["free/a","free/b"])
        XCTAssertFalse(models.contains{$0.id.contains("openai")})
        XCTAssertFalse(models.first{$0.id=="paid/c"}!.free)
    }
    func testFallbackWithMockedNetworkAndFreePriceCeiling() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog),(503,Data()),(200,Self.answer(#"{"choice":"off_task","p_on":0.01,"p_off":0.98,"p_uncertain":0.01}"#))])
        let client=OpenRouterClient(transport:mock)
        let decision=try await client.classify(jpeg:Data([1]),ocr:"synthetic",app:"Test",task:"Synthetic task",key:"test-only")
        XCTAssertEqual(decision.activity,.offTask)
        let requests=await mock.requests
        XCTAssertEqual(requests.count,3)
        for request in requests.dropFirst() {
            let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
            XCTAssertTrue((body["model"] as! String).hasPrefix("free/"))
            let provider=body["provider"] as! [String:Any],prices=provider["max_price"] as! [String:Double]
            XCTAssertEqual(prices["prompt"],0);XCTAssertEqual(prices["completion"],0)
        }
    }
    func testPaidFallbackRequiresExplicitOptInAndStaysCheap() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog),(503,Data()),(503,Data()),(200,Self.answer(#"{"choice":"on_task","p_on":1,"p_off":0,"p_uncertain":0}"#))])
        let client=OpenRouterClient(transport:mock)
        let result=try await client.classify(jpeg:Data(),ocr:"synthetic",app:"Test",task:"synthetic",key:"synthetic",allowPaid:true)
        XCTAssertEqual(result.activity,.onTask)
        let requests=await mock.requests
        let body=try JSONSerialization.jsonObject(with:requests.last!.httpBody!) as! [String:Any]
        XCTAssertEqual(body["model"] as? String,"paid/c")
        let provider=body["provider"] as! [String:Any],price=provider["max_price"] as! [String:Double]
        XCTAssertEqual(price["prompt"],0.2);XCTAssertEqual(price["completion"],0.8)
    }
    func testMalformedDoesNotTriggerExtraRequests() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog),(200,Self.answer("bad json"))])
        let client=OpenRouterClient(transport:mock)
        let value=try await client.classify(jpeg:Data(),ocr:"",app:"",task:"",key:"synthetic")
        XCTAssertEqual(value.activity,.uncertain)
        let n=await mock.requests.count;XCTAssertEqual(n,2)
    }
    func testPrivateScreenPreventsCompletionRequest() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog)])
        do {
            _=try await OpenRouterClient(transport:mock).classify(jpeg:Data(),ocr:"",app:"",task:"",key:"synthetic",permitsSend:{false})
            XCTFail("Private screen must never be sent")
        } catch { XCTAssertEqual(error as? RouterError,.privateScreen) }
        let n=await mock.requests.count;XCTAssertEqual(n,1) // Only public model catalogue fetched.
    }
    func testRateLimitStopsFallbackAndPreservesBudget() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog),(429,Data())])
        let client=OpenRouterClient(transport:mock)
        do { _=try await client.classify(jpeg:Data(),ocr:"",app:"",task:"",key:"synthetic");XCTFail() }
        catch { XCTAssertEqual(error as? RouterError,.dailyLimit) }
        let text=await client.nudge(task:"synthetic",key:"synthetic")
        XCTAssertEqual(text,OpenRouterClient.fallbackNudge)
        let n=await mock.requests.count;XCTAssertEqual(n,2)
    }
    func testWeeklyCacheRefreshAndNoStalePriceFallback() async throws {
        let mock=MockTransport(replies:[(200,Self.catalog),(503,Data())])
        let client=OpenRouterClient(transport:mock),now=Date()
        _=try await client.models(vision:true,allowPaid:false,now:now)
        _=try await client.models(vision:true,allowPaid:false,now:now.addingTimeInterval(6*86400))
        do { _=try await client.models(vision:true,allowPaid:false,now:now.addingTimeInterval(7*86400));XCTFail() } catch {}
        let n=await mock.requests.count;XCTAssertEqual(n,2)
    }
    static let catalog=Data(#"{"data":[{"id":"free/a","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]},"pricing":{"prompt":"0","completion":"0"}},{"id":"free/b","architecture":{"input_modalities":["image","text"],"output_modalities":["text"]},"pricing":{"prompt":"0","completion":"0","request":"0"}},{"id":"free/text","architecture":{"input_modalities":["text"],"output_modalities":["text"]},"pricing":{"prompt":"0","completion":"0"}},{"id":"paid/c","architecture":{"input_modalities":["image"],"output_modalities":["text"]},"pricing":{"prompt":"0.0000001","completion":"0.0000005"}},{"id":"openai/anything","architecture":{"input_modalities":["image"],"output_modalities":["text"]},"pricing":{"prompt":"0","completion":"0"}}]}"#.utf8)
    static func answer(_ text:String)->Data { try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":text]]],"usage":["cost":0]]) }
}
actor MockTransport:HTTPTransport {
    var replies:[(Int,Data)]
    private(set) var requests:[URLRequest]=[]
    init(replies:[(Int,Data)]) { self.replies=replies }
    func data(for request:URLRequest) async throws -> (Data,HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw RouterError.unavailable }
        let reply=replies.removeFirst()
        return (reply.1,HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:nil)!)
    }
}
