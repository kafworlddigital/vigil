import Foundation
struct ConnectionResult:Identifiable {
    var id:String { provider }
    var provider:String
    var model:String
    var ok:Bool
    var detail:String
}
enum ConnectionTester {
    static func run() async -> [ConnectionResult] {
        var result:[ConnectionResult]=[]
        for provider in ["OpenRouter","OpenCode"] {
            let service="com.kafworlddigital.vigil."+(provider == "OpenRouter" ? "openrouter":"opencode")
            guard let key=KeyVault.read(service:service) else {result.append(ConnectionResult(provider:provider,model:"No model",ok:false,detail:"Save a key on this device first."));continue}
            do {
                let model:String
                let endpoint:String
                var body:[String:Any]
                if provider == "OpenRouter" {
                    let client=OpenRouterClient()
                    let models=try await client.models(vision:true,allowPaid:false)
                    guard let selected=models.first(where:{$0.id.contains("gemma-4-26b")}) ?? models.first else{throw RouterError.unavailable}
                    model=selected.id;endpoint="https://openrouter.ai/api/v1/chat/completions"
                    // Synthetic image only. Never capture a desktop for a connection test.
                    let png="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII="
                    body=["model":model,"messages":[["role":"user","content":[["type":"text","text":"Reply OK if you received this test image."],["type":"image_url","image_url":["url":"data:image/png;base64,"+png]]]]],"max_tokens":192,"reasoning":["enabled":false],"provider":["max_price":["prompt":0,"completion":0,"request":0,"image":0]]]
                }else{
                    model="mimo-v2.6-flash-free";endpoint="https://opencode.ai/inference/openai/v1/chat/completions"
                    body=["model":model,"messages":[["role":"user","content":"Reply OK."]],"max_tokens":192]
                }
                var request=URLRequest(url:URL(string:endpoint)!);request.httpMethod="POST";request.timeoutInterval=35
                request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.httpBody=try JSONSerialization.data(withJSONObject:body)
                let (data,response)=try await URLTransport().data(for:request)
                let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
                let choices=json?["choices"] as? [[String:Any]]
                let message=choices?.first?["message"] as? [String:Any]
                let text=message?["content"] as? String ?? ""
                let ok=response.statusCode==200 && !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
                let detail=ok ? "Answered · free" : provider == "OpenCode" && response.statusCode==403 ? "Free models require the official OpenCode client." : "HTTP \(response.statusCode) · no answer. Try again later."
                result.append(ConnectionResult(provider:provider,model:model,ok:ok,detail:detail))
            }catch{result.append(ConnectionResult(provider:provider,model:"Free model",ok:false,detail:"Connection unavailable. Your key has not been changed."))}
        }
        return result
    }
}
