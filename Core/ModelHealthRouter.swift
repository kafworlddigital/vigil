import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ModelCandidate: Codable, Sendable, Equatable, Identifiable {
    public var provider: String
    public var model: String
    public var vision: Bool
    public var endpoint: String
    public var name: String
    public var wireProtocol: String
    public var id: String { provider + ":" + model }
    enum CodingKeys: String, CodingKey { case provider, model, vision, endpoint, name; case wireProtocol = "protocol" }
    public init(provider:String,model:String,vision:Bool,endpoint:String,name:String? = nil,wireProtocol:String = "chat") {
        self.provider=provider;self.model=model;self.vision=vision;self.endpoint=endpoint;self.name=name ?? model;self.wireProtocol=wireProtocol
    }
    public var permitted: Bool {
        let lower=model.lowercased()
        guard !["openai","gpt","codex"].contains(where:lower.contains),let url=URL(string:endpoint),url.scheme=="https" else { return false }
        let hosts=["opencode-go":"opencode.ai","opencode":"opencode.ai","openrouter":"openrouter.ai","nvidia":"integrate.api.nvidia.com","ollama-cloud":"ollama.com"]
        return hosts[provider]==url.host && !(provider=="openrouter" && lower.hasPrefix("openrouter/"))
    }
}
public struct ModelHealth: Codable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var model: String
    public var vision: Bool
    public var status = "amber"
    public var latency: Double?
    public var error: String?
    public var checkedAt: Date?
    public var cooldownUntil: Date?
    public init(_ candidate:ModelCandidate) { id=candidate.id;provider=candidate.provider;model=candidate.model;vision=candidate.vision }
    public func resting(_ now:Date)->Bool { (cooldownUntil ?? .distantPast)>now }
}
public struct ModelReply: Codable, Sendable {
    public var text: String
    public var provider: String
    public var model: String
    public var local: Bool
    public init(text:String,provider:String,model:String,local:Bool = false) { self.text=text;self.provider=provider;self.model=model;self.local=local }
}
public struct ModelPrompt: Sendable {
    public var system: String
    public var text: String
    public var image: Data?
    public var mime: String
    public var screen: Bool { image != nil }
    public init(system:String = "",text:String,image:Data? = nil,mime:String = "image/jpeg") { self.system=system;self.text=text;self.image=image;self.mime=mime }
}

/// Stateless prompts, persisted health only. A failed provider never prevents the next provider or local reply.
public actor ModelHealthRouter {
    private let candidates:[ModelCandidate]
    private let transport:any HTTPTransport
    private let healthURL:URL?
    private var keys:[String:String]
    private var health:[String:ModelHealth]=[:]
    private var probing=false
    private let sessionID="vigil-"+UUID().uuidString
    public init(candidates:[ModelCandidate],keys:[String:String],transport:any HTTPTransport = URLTransport(),healthURL:URL? = nil) {
        self.candidates=candidates.filter(\.permitted);self.keys=keys;self.transport=transport;self.healthURL=healthURL
        if let healthURL,let data=try? Data(contentsOf:healthURL),let records=try? JSONDecoder().decode([ModelHealth].self,from:data) {
            for record in records { health[record.id]=record }
        }
        for candidate in self.candidates where health[candidate.id]==nil { health[candidate.id]=ModelHealth(candidate) }
    }
    public func setKeys(_ value:[String:String]) { keys=value }
    /// Reuse the authenticated brain's checks instead of spending the same allowance twice.
    public func importHealth(_ records:[ModelHealth]) {
        for state in records {
            guard let candidate=candidates.first(where:{$0.id==state.id}),candidate.provider==state.provider,candidate.model==state.model,
                  ["green","amber","red"].contains(state.status) else{continue}
            if (state.checkedAt ?? .distantPast)>=(health[state.id]?.checkedAt ?? .distantPast) {health[state.id]=state}
        }
        persist()
    }
    public func snapshot()->[ModelHealth] { candidates.compactMap{health[$0.id]}.sorted{ a,b in
        let ranks=["green":0,"amber":1,"red":2]
        if ranks[a.status,default:2] != ranks[b.status,default:2] { return ranks[a.status,default:2]<ranks[b.status,default:2] }
        if a.status=="green",a.latency != b.latency { return (a.latency ?? 20)<(b.latency ?? 20) }
        return a.id<b.id
    } }
    public func probeAll(now:Date = Date()) async {
        guard !probing else { return };probing=true;defer { probing=false;persist() }
        let jobs=candidates.filter{!(health[$0.id]?.resting(now) ?? false)}
        let transport=self.transport,keys=self.keys,session=self.sessionID
        await withTaskGroup(of:ModelHealth.self) { group in
            for candidate in jobs {
                group.addTask {
                    var state=ModelHealth(candidate);state.checkedAt=now
                    guard let key=keys[candidate.provider],!key.isEmpty else { state.status="red";state.error="auth: key missing";return state }
                    let start=Date()
                    do {
                        // Vision candidates must actually accept an image, not merely a text probe.
                        let image=candidate.vision ? Self.probePNG : nil
                        let prompt=ModelPrompt(text:image == nil ? "Reply ready." : "Reply ready if you can see this plain image.",image:image,mime:"image/png")
                        let request=try Self.request(candidate,prompt:prompt,key:key,session:session,timeout:20,probe:true)
                        let (data,response)=try await transport.data(for:request)
                        _=try Self.answer(data,response:response,candidate:candidate,now:now)
                        state.status="green";state.latency=Date().timeIntervalSince(start)
                    } catch {
                        state=Self.failed(candidate,error:error,now:now);state.latency=Date().timeIntervalSince(start)
                    }
                    return state
                }
            }
            for await state in group { health[state.id]=state }
        }
    }
    public func complete(_ prompt:ModelPrompt,permitsSend:@escaping @Sendable () async -> Bool = {true}) async throws -> ModelReply {
        let now=Date()
        let ordered=snapshot().compactMap { state -> ModelCandidate? in
            guard !state.resting(now),let candidate=candidates.first(where:{$0.id==state.id}),(!prompt.screen || candidate.vision),!(keys[candidate.provider] ?? "").isEmpty else { return nil }
            return candidate
        }
        for candidate in ordered {
            try Task.checkCancellation()
            guard await permitsSend() else { throw RouterError.privateScreen }
            let timeout:Double=20
            do {
                let request=try Self.request(candidate,prompt:prompt,key:keys[candidate.provider]!,session:sessionID,timeout:timeout,probe:false)
                let sent=Date();let (data,response)=try await transport.data(for:request)
                let text=try Self.answer(data,response:response,candidate:candidate,now:Date())
                if prompt.screen { _=try FocusDecision.decode(Data(Self.cleanJSON(text).utf8)) }
                var state=ModelHealth(candidate);state.status="green";state.checkedAt=Date();state.latency=Date().timeIntervalSince(sent);health[candidate.id]=state;persist()
                return ModelReply(text:Self.cleanJSON(text),provider:candidate.provider,model:candidate.model)
            } catch is CancellationError { throw CancellationError() }
              catch { health[candidate.id]=Self.failed(candidate,error:error,now:Date());persist() }
        }
        guard await permitsSend() else { throw RouterError.privateScreen }
        return Self.localReply(prompt)
    }
    public static func localReply(_ prompt:ModelPrompt)->ModelReply {
        if prompt.screen {
            // Conservative local heuristic: a matching task word is context, never proof of drift.
            let lines=prompt.text.lowercased().components(separatedBy:"\n")
            let words=Set((lines.first ?? "").split{!$0.isLetter}.map(String.init).filter{$0.count>4})
            let evidence=lines.dropFirst().joined(separator:" ")
            let overlap=words.filter{evidence.contains($0)}.count
            let on=overlap>=2
            let json=on ? #"{"choice":"on_task","p_on":0.6,"p_off":0.0,"p_uncertain":0.4}"# : #"{"choice":"uncertain","p_on":0.0,"p_off":0.0,"p_uncertain":1.0}"#
            return ModelReply(text:json,provider:"on-device",model:"Local screen heuristic",local:true)
        }
        return ModelReply(text:"One small step towards your task. Your timer and parking lot are ready when you are.",provider:"on-device",model:"Local reply",local:true)
    }
    private struct Failure:Error { var kind:String;var reset:Date? }
    private static func failed(_ candidate:ModelCandidate,error:Error,now:Date)->ModelHealth {
        var state=ModelHealth(candidate);state.checkedAt=now
        if let error=error as? Failure { state.error=error.kind;state.cooldownUntil=error.reset;state.status=error.kind=="limit" || error.kind=="429" ? "amber":"red" }
        else if let error=error as? URLError { state.error=error.code == .timedOut ? "timeout":"network";state.status="red";state.cooldownUntil=now.addingTimeInterval(60) }
        else { state.error="invalid reply";state.status="red";state.cooldownUntil=now.addingTimeInterval(60) }
        return state
    }
    private static func answer(_ data:Data,response:HTTPURLResponse,candidate:ModelCandidate,now:Date)throws->String {
        guard (200..<300).contains(response.statusCode) else {
            let body=String(data:data,encoding:.utf8)?.lowercased() ?? ""
            if response.statusCode==429 || ["limit reached","quota","rate limit","usage limit"].contains(where:body.contains) {
                let seconds=Double(response.value(forHTTPHeaderField:"Retry-After") ?? "")
                let fmt=DateFormatter();fmt.locale=Locale(identifier:"en_US_POSIX");fmt.timeZone=TimeZone(secondsFromGMT:0);fmt.dateFormat="EEE, dd MMM yyyy HH:mm:ss z"
                let reset=seconds.map{now.addingTimeInterval(max(1,$0))} ?? response.value(forHTTPHeaderField:"Retry-After").flatMap{fmt.date(from:$0)} ?? now.addingTimeInterval(1800)
                throw Failure(kind:response.statusCode==429 ? "429":"limit",reset:reset)
            }
            if [401,403].contains(response.statusCode) {throw Failure(kind:"auth",reset:now.addingTimeInterval(1800))}
            throw Failure(kind:"http \(response.statusCode)",reset:now.addingTimeInterval(response.statusCode==402 ? 1800:60))
        }
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw RouterError.invalidReply }
        let text:String?
        if candidate.wireProtocol=="ollama" { text=(object["message"] as? [String:Any])?["content"] as? String }
        else { text=((object["choices"] as? [[String:Any]])?.first?["message"] as? [String:Any])?["content"] as? String }
        guard let text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw RouterError.invalidReply }
        return text.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func request(_ candidate:ModelCandidate,prompt:ModelPrompt,key:String,session:String,timeout:Double,probe:Bool)throws->URLRequest {
        guard candidate.permitted,let url=URL(string:candidate.endpoint) else { throw RouterError.unavailable }
        var messages:[[String:Any]]=[]
        if !prompt.system.isEmpty {messages.append(["role":"system","content":String(prompt.system.prefix(2000))])}
        if let image=prompt.image {
            if candidate.wireProtocol=="ollama" { messages.append(["role":"user","content":String(prompt.text.prefix(14000)),"images":[image.base64EncodedString()]]) }
            else {messages.append(["role":"user","content":[["type":"text","text":String(prompt.text.prefix(14000))],["type":"image_url","image_url":["url":"data:\(prompt.mime);base64,\(image.base64EncodedString())"]]]])}
        } else { messages.append(["role":"user","content":String(prompt.text.prefix(14000))]) }
        var body:[String:Any]=["model":candidate.model,"messages":messages,"stream":false,"max_tokens":probe ? 256:512]
        if candidate.wireProtocol=="ollama" {body.removeValue(forKey:"max_tokens");body["think"]=false;body["options"]=["num_predict":probe ? 256:512]}
        if candidate.provider=="openrouter" {body["provider"]=["max_price":["prompt":0,"completion":0,"request":0,"image":0]];body["reasoning"]=["enabled":false]}
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:timeout)
        request.httpMethod="POST";request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("Vigil/1.0",forHTTPHeaderField:"User-Agent");request.setValue(session,forHTTPHeaderField:"x-opencode-session")
        request.httpBody=try JSONSerialization.data(withJSONObject:body);return request
    }
    public static func cleanJSON(_ text:String)->String {
        var s=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if s.hasPrefix("```"),let start=s.firstIndex(of:"\n"),let end=s.range(of:"```",options:.backwards),start<end.lowerBound {s=String(s[s.index(after:start)..<end.lowerBound])}
        return s.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private func persist() { if let healthURL {try? JSONEncoder().encode(snapshot()).write(to:healthURL,options:.atomic)} }
    // Valid 256px synthetic image is supplied by the app's asset pack; never a user's screen.
    public static var probePNG:Data { Data(base64Encoded:probeImageBase64) ?? Data() }
    public static let probeImageBase64="iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAACwUlEQVR4nO3TMQ0AMAzAsPIHsHsQB2EwesSSAeTJnPsga9YLYJEBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5BmANIMQJoBSDMAaQYgzQCkGYA0A5D2Ae8OIDsG4ElaAAAAAElFTkSuQmCC"
}
