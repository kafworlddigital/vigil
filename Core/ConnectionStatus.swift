import Foundation

struct ConnectionResult:Identifiable,Codable {
    var id:String {provider}
    var provider:String;var model:String;var ok:Bool;var detail:String
}
enum ConnectionStatus {
    static func results(_ models:[ModelHealth],viaBrain:Bool,now:Date=Date())->[ConnectionResult] {
        [("OpenRouter",["openrouter"]),("OpenCode",["opencode-go","opencode"]),("NVIDIA",["nvidia"])].map { label,providers in
            let states=models.filter{providers.contains($0.provider)}
            let answered=states.filter {state in
                guard state.status=="green",let checked=state.checkedAt else{return false}
                return now.timeIntervalSince(checked)>=(-60) && now.timeIntervalSince(checked)<=300
            }.sorted{($0.latency ?? 100)<($1.latency ?? 100)}.first
            if let answered {
                return ConnectionResult(provider:label,model:answered.model,ok:true,
                    detail:viaBrain ? "Answered via Vigil brain · \(answered.provider)":"Answered on this device · \(answered.provider)")
            }
            let detail=states.first(where:{$0.status != "green"})?.error ?? "No recent answer. Test again when the connection is available."
            return ConnectionResult(provider:label,model:states.first?.model ?? "Waiting",ok:false,detail:detail)
        }
    }
}
