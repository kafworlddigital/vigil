import Foundation
import StoreKit

extension VigilAI {
    /// TestFlight authenticates the install with Apple's signed app transaction.
    /// There is no bundled provider key, account form or shared device token.
    func enrolAutomatically() async {
        guard KeyVault.read(service:"com.kafworlddigital.vigil.brain")==nil else{return}
        let args=ProcessInfo.processInfo.arguments
        guard !args.contains("--vigil-proof"),!args.contains("--vigil-screen"),!args.contains("--vigil-renderer-fixture") else{return}
        // A legacy receipt file is not guaranteed on iPhone TestFlight. Managed editions use StoreKit's signed transaction directly.
        if !VigilEdition.managed {
            guard let receipt=Bundle.main.appStoreReceiptURL,FileManager.default.fileExists(atPath:receipt.path) else{return}
        }
        do {
            let verification=try await AppTransaction.shared
            guard case .verified=verification else{return}
            var device=KeyVault.read(service:"com.kafworlddigital.vigil.installation")
            if device==nil {device=UUID().uuidString;try KeyVault.write(device!,service:"com.kafworlddigital.vigil.installation")}
            var request=URLRequest(url:Self.brainURL.appendingPathComponent("enrol"),timeoutInterval:20)
            request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:["transaction":verification.jwsRepresentation,"device":device!,"bundle":Bundle.main.bundleIdentifier ?? ""])
            let (data,response)=try await URLTransport().data(for:request)
            guard response.statusCode==200,let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],let token=json["token"] as? String else{return}
            try KeyVault.write(token,service:"com.kafworlddigital.vigil.brain")
            message="Connected securely. No account or key needed."
        }catch {message="On-device help is ready. The server will reconnect when available."}
    }
}
