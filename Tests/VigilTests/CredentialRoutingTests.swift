import XCTest
@testable import VigilCore

final class CredentialRoutingTests:XCTestCase {
    private func record(_ provider:String="OpenRouter",id:UUID=UUID(),secret:String="SYNTHETIC_ONLY",status:String="working")->[String:Any] {
        ["id":id.uuidString,"title":provider+" API key","kind":"apiKey","provider":provider,"secret":secret,
         "website":"","usedIn":"","updateLocation":"","status":status,"createdAt":0,"updatedAt":1]
    }
    private func legacy(_ record:[String:Any]) throws->TuckCredentials.Item {
        .init(account:record["id"] as! String,data:try JSONSerialization.data(withJSONObject:record))
    }
    private func revision(_ record:[String:Any],id:String=UUID().uuidString,parents:[String]=[],deleted:Bool=false) throws->TuckCredentials.Item {
        let data:[String:Any]=["formatVersion":2,"id":id,"parentIDs":parents,"record":record,"isDeleted":deleted,"writtenAt":2]
        return .init(account:(record["id"] as! String)+":"+id,data:try JSONSerialization.data(withJSONObject:data))
    }
    func testImportsAllSupportedProvidersWithoutConfusingGoAndZen() throws {
        let providers=["OpenRouter","OpenCode Go","OpenCode","NVIDIA","Ollama Cloud"]
        let items=try providers.map{try legacy(record($0))}
        XCTAssertEqual(Set(TuckCredentials.select(items).keys),Set(["openrouter","opencode-go","opencode","nvidia","ollama-cloud"]))
    }
    func testIgnoresPasswordsRetiredAndUnknownProviders() throws {
        var password=record();password["kind"]="password"
        let items=try [password,record("NVIDIA",status:"retired"),record("Unknown")].map(legacy)
        XCTAssertTrue(TuckCredentials.select(items).isEmpty)
    }
    func testConflictsAndAmbiguousProviderRecordsAreNotImported() throws {
        let id=UUID(),left=record(id:id),right=record(id:id,secret:"OTHER_SYNTHETIC")
        XCTAssertTrue(TuckCredentials.select(try [revision(left),revision(right)]).isEmpty)
        XCTAssertTrue(TuckCredentials.select(try [legacy(record()),legacy(record(secret:"OTHER_SYNTHETIC"))]).isEmpty)
    }
    func testLatestRevisionAndDeletionWinOverParent() throws {
        let old=record(),parent=UUID().uuidString
        var new=old;new["secret"]="ROTATED_SYNTHETIC"
        let previous=try revision(old,id:parent)
        XCTAssertEqual(TuckCredentials.select(try [previous,revision(new,parents:[parent])])["openrouter"],"ROTATED_SYNTHETIC")
        XCTAssertTrue(TuckCredentials.select(try [previous,revision(new,parents:[parent],deleted:true)]).isEmpty)
    }
    func testCorruptRevisionQuarantinesTheWholeRecord() throws {
        let value=record(),good=try legacy(value)
        let bad=TuckCredentials.Item(account:(value["id"] as! String)+":"+UUID().uuidString,data:Data("invalid".utf8))
        XCTAssertTrue(TuckCredentials.select([good,bad]).isEmpty)
    }
    func testVersionCycleIsNeverSelected() throws {
        let value=record(),a=UUID().uuidString,b=UUID().uuidString
        XCTAssertTrue(TuckCredentials.select(try [revision(value,id:a,parents:[b]),revision(value,id:b,parents:[a])]).isEmpty)
    }
    func testConnectionResultsUseGoAndNvidiaActualAnswersWithoutLocalKeys() {
        let now=Date()
        let models=[("openrouter","or"),("opencode-go","go"),("nvidia","nim")].map {provider,model in
            var state=ModelHealth(ModelCandidate(provider:provider,model:model,vision:false,endpoint:"https://example.invalid"))
            state.status="green";state.checkedAt=now;return state
        }
        let results=ConnectionStatus.results(models,viaBrain:true,now:now)
        XCTAssertEqual(results.count,3);XCTAssertTrue(results.allSatisfy{$0.ok && $0.detail.contains("Vigil brain")})
        XCTAssertEqual(results.first{$0.provider=="OpenCode"}?.model,"go")
        XCTAssertTrue(ConnectionStatus.results(models,viaBrain:true,now:now.addingTimeInterval(301)).allSatisfy{!$0.ok})
    }
    func testAuthenticatedBrainReplacesNewerLocalMissingKeyState() async {
        let candidate=ModelCandidate(provider:"nvidia",model:"synthetic",vision:false,endpoint:"https://integrate.api.nvidia.com/v1/chat/completions")
        let router=ModelHealthRouter(candidates:[candidate],keys:[:])
        await router.probeAll(now:Date().addingTimeInterval(30))
        var cloud=ModelHealth(candidate);cloud.status="green";cloud.checkedAt=Date()
        await router.importHealth([cloud],authoritative:true)
        var states=await router.snapshot();XCTAssertEqual(states.first?.status,"green")
        await router.brainUnavailable()
        states=await router.snapshot();XCTAssertEqual(states.first?.status,"amber")
        XCTAssertFalse(states.first?.error?.contains("key missing") ?? true)
    }
}
