import Foundation
import CryptoKit

/// Read Tuck's versioned shared vault without changing any of its records.
enum TuckCredentials {
    struct Item { var account:String; var data:Data }
    private struct Record:Codable,Equatable {
        var id:UUID;var title:String;var kind:String;var provider:String;var secret:String
        var website:String;var usedIn:String;var updateLocation:String;var status:String
        var createdAt:Date;var updatedAt:Date
    }
    private struct Revision:Decodable {
        var formatVersion:Int;var id:String;var parentIDs:[String];var record:Record
        var isDeleted:Bool;var writtenAt:Date
    }
    private struct Node {var id:String;var parents:[String];var record:Record;var deleted:Bool}
    static func select(_ items:[Item])->[String:String] {
        var records:[UUID:[String:Node]]=[:];var blocked=Set<UUID>()
        for item in items {
            let parts=item.account.split(separator:":",maxSplits:1).map(String.init)
            guard let first=parts.first,let recordID=UUID(uuidString:first) else{continue}
            guard item.data.count<=128*1024 else{blocked.insert(recordID);continue}
            do {
                let node:Node
                if parts.count==1 {
                    let record=try JSONDecoder().decode(Record.self,from:item.data)
                    guard record.id==recordID else{blocked.insert(recordID);continue}
                    node=Node(id:try legacyID(record),parents:[],record:record,deleted:false)
                }else{
                    let revision=try JSONDecoder().decode(Revision.self,from:item.data)
                    guard revision.formatVersion==2,revision.record.id==recordID,revision.id==parts[1],
                          validID(revision.id),revision.parentIDs.count<=128,
                          revision.parentIDs.allSatisfy(validID),!revision.parentIDs.contains(revision.id),
                          revision.writtenAt.timeIntervalSinceReferenceDate.isFinite else{blocked.insert(recordID);continue}
                    if revision.id.hasPrefix("legacy:") {
                        guard revision.id == (try legacyID(revision.record)),revision.parentIDs.isEmpty,
                              !revision.isDeleted,revision.writtenAt==revision.record.updatedAt else{blocked.insert(recordID);continue}
                    }
                    node=Node(id:revision.id,parents:revision.parentIDs,record:revision.record,deleted:revision.isDeleted)
                }
                if let old=records[recordID]?[node.id],old.record != node.record || old.parents != node.parents || old.deleted != node.deleted {
                    blocked.insert(recordID);continue
                }
                records[recordID,default:[:]][node.id]=node
            }catch{blocked.insert(recordID)}
        }
        var candidates:[String:Set<String>]=[:]
        for (id,versions) in records where !blocked.contains(id) {
            var pending=versions;var visited=Set<String>()
            while !pending.isEmpty {
                let ready=pending.values.filter{$0.parents.allSatisfy{versions[$0]==nil || visited.contains($0)}}.map(\.id)
                if ready.isEmpty{break}
                for id in ready{visited.insert(id);pending.removeValue(forKey:id)}
            }
            guard pending.isEmpty else{continue}
            let parents=Set(versions.values.flatMap(\.parents))
            let heads=versions.values.filter{!parents.contains($0.id)}
            guard heads.count==1,let head=heads.first,!head.deleted else{continue}
            let record=head.record
            guard record.kind=="apiKey",["unchecked","working"].contains(record.status),let provider=provider(record) else{continue}
            let secret=record.secret.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !secret.isEmpty else{continue}
            candidates[provider,default:[]].insert(secret)
        }
        return candidates.reduce(into:[:]){result,pair in if pair.value.count==1{result[pair.key]=pair.value.first}}
    }
    private static func validID(_ id:String)->Bool {
        UUID(uuidString:id) != nil || (id.hasPrefix("legacy:") && id.count==71 && id.dropFirst(7).allSatisfy{"0123456789abcdef".contains($0)})
    }
    private static func legacyID(_ record:Record) throws->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return "legacy:"+SHA256.hash(data:try encoder.encode(record)).map{String(format:"%02x",$0)}.joined()
    }
    private static func provider(_ record:Record)->String? {
        func normal(_ value:String)->String {value.lowercased().filter{$0.isLetter || $0.isNumber}}
        let name=normal(record.provider),title=normal(record.title)
        let aliases:[String:String]=["openrouter":"openrouter","nvidia":"nvidia","nvidianim":"nvidia",
            "opencodego":"opencode-go","opencode":"opencode","opencodezen":"opencode",
            "ollama":"ollama-cloud","ollamacloud":"ollama-cloud"]
        if name=="opencode",title.contains("opencodego"){return "opencode-go"}
        if let value=aliases[name]{return value}
        if name.isEmpty,let value=aliases[title.replacingOccurrences(of:"apikey",with:"")]{return value}
        if title=="orcaapikey",record.secret.hasPrefix("sk-or-"){return "openrouter"}
        return nil
    }
}
