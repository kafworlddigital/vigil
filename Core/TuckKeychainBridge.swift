import Foundation
import Security

enum TuckKeychainBridge {
    static let group="V892V3PC6T.com.kafworlddigital.tuck.shared"
    /// Never search the legacy login Keychain, which previously blocked Vigil's UI.
    static func refresh()->Int {
        #if VIGIL_MACY
        return 0
        #else
        guard !VigilEdition.macy else{return 0}
        var items:[TuckCredentials.Item]=[]
        for service in ["com.kafworlddigital.tuck.vault.v1","com.kafworlddigital.tuck.vault.v1.versions.v2"] {
            var query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
                kSecAttrService as String:service,kSecAttrAccessGroup as String:group,
                kSecAttrSynchronizable as String:true,kSecMatchLimit as String:kSecMatchLimitAll,
                kSecReturnData as String:true,kSecReturnAttributes as String:true,
                kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String]=true
            #endif
            var result:CFTypeRef?
            let status=SecItemCopyMatching(query as CFDictionary,&result)
            if status==errSecItemNotFound{continue}
            guard status==errSecSuccess,let values=result as? [[String:Any]] else{return 0}
            for value in values {
                guard let account=value[kSecAttrAccount as String] as? String,let data=value[kSecValueData as String] as? Data else{return 0}
                items.append(.init(account:account,data:data))
            }
        }
        var imported=0
        for (provider,key) in TuckCredentials.select(items) {
            let service="com.kafworlddigital.vigil."+provider
            if KeyVault.read(service:service)==key{continue}
            do{try KeyVault.write(key,service:service);imported+=1}catch{continue}
        }
        return imported
        #endif
    }
}
