import XCTest
@testable import VigilTransport
final class SecureChannelTests:XCTestCase {
    func testVigilPairingRoundTripAndRejectsBlueyCode() {
        let record=PairingRecord(service:"Synthetic Mac",secret:Data(repeating:7,count:32))
        XCTAssertEqual(PairingRecord.parse(record.qrText),record)
        XCTAssertNil(PairingRecord.parse(record.qrText.replacingOccurrences(of:"vigil-pair:",with:"bluey-pair:")))
    }
    func testAuthenticatedEncryptedTransportRejectsReplayWrongKeyAndTamper() throws {
        let secret=Data(repeating:3,count:32),challenge=Data(repeating:4,count:32)
        var server=SecureChannel(secret:secret,challenge:challenge,server:true)
        var client=SecureChannel(secret:secret,challenge:challenge,server:false)
        let sealed=try server.seal(Packet(command:"focusPark",text:"synthetic idea"))
        XCTAssertFalse(String(data:sealed,encoding:.utf8)!.contains("synthetic idea"))
        XCTAssertEqual(try client.open(sealed).text,"synthetic idea")
        XCTAssertThrowsError(try client.open(sealed))
        var wrong=SecureChannel(secret:Data(repeating:2,count:32),challenge:challenge,server:false)
        XCTAssertThrowsError(try wrong.open(sealed))
        var corrupted=sealed;corrupted[corrupted.startIndex]=0
        XCTAssertThrowsError(try client.open(corrupted))
    }
}

final class VigilMoodCompatibilityTests:XCTestCase {
    func testAllOriginalMoodsAndSurpriseRoundTrip() throws {
        for mood in Mood.allCases {
            let face=FaceState(gazeX:-0.8,gazeY:0.75,mood:mood)
            let data=try JSONEncoder().encode(Packet(face:face))
            XCTAssertEqual(try JSONDecoder().decode(Packet.self,from:data).face,face)
        }
        XCTAssertNotNil(Mood(rawValue:"listening"));XCTAssertNotNil(Mood(rawValue:"surprised"))
    }
}
