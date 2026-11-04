import Foundation
#if canImport(Security)
import Security

enum KeyVault {
    static func read(service: String = "com.kafworlddigital.vigil.openrouter", account: String = "api-key") -> String? {
        var query=base(service,account)
        query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String]=kSecUseAuthenticationUIFail
        var item:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,let data=item as? Data,
              let value=String(data:data,encoding:.utf8),!value.isEmpty else { return nil }
        return value
    }
    static func write(_ value:String,service:String="com.kafworlddigital.vigil.openrouter",account:String="api-key") throws {
        let query=base(service,account)
        let clean=value.trimmingCharacters(in:.whitespacesAndNewlines)
        if clean.isEmpty { SecItemDelete(query as CFDictionary);return }
        let updates=[kSecValueData as String:Data(clean.utf8)] as [String:Any]
        var status=SecItemUpdate(query as CFDictionary,updates as CFDictionary)
        if status==errSecItemNotFound {
            var item=query;item[kSecValueData as String]=Data(clean.utf8)
            item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status=SecItemAdd(item as CFDictionary,nil)
        }
        guard status==errSecSuccess else { throw VaultError.saveFailed }
    }
    private static func base(_ service:String,_ account:String)->[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:(VigilEdition.macy && !service.contains(".vigil.m.") ? service.replacingOccurrences(of:"com.kafworlddigital.vigil.",with:"com.kafworlddigital.vigil.m."):service),kSecAttrAccount as String:account]
    }
    #if os(macOS)
    static func importTuckIfAvailable()->Bool {
        guard !VigilEdition.macy else { return false }
        if read() != nil { return true }
        for attribute in [kSecAttrLabel,kSecAttrAccount] {
            let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,attribute as String:"Orca API Key",
                kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,
                kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
            var item:CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,let data=item as? Data,
               let value=String(data:data,encoding:.utf8),value.hasPrefix("sk-or-") {
                do { try write(value); return true } catch { return false }
            }
        }
        return false
    }
    #endif
    private enum VaultError:LocalizedError {
        case saveFailed
        var errorDescription:String? { "Couldn't save that key securely. Please try again." }
    }
}
#endif
