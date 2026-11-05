import XCTest
@testable import VigilCore

final class SupportTests: XCTestCase {
    func testSpokenAndTypedSupportCommands() {
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil, I’m stuck"), .stuck(""))
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil I am stuck"), .stuck(""))
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil, remind me in 15 minutes to send the draft"), .remind(minutes: 15, text: "send the draft"))
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil remind me in twenty five minutes to stretch"), .remind(minutes: 25, text: "stretch"))
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil remind me in one minute"), .remind(minutes: 1, text: ""))
    }
    func testReminderBoundsAndWakeName() {
        for value in ["Vigil remind me in 0 minutes", "Vigil remind me in 1441 minutes", "Vigil remind me in -5 minutes", "Remind me in 5 minutes", "Vigil remind me in minutes", "Vigil remind me in 1.5 minutes"] {
            XCTAssertNil(VigilVoiceCommand.parse(value), value)
        }
        XCTAssertEqual(VigilVoiceCommand.parse("Vigil remind me in 1440 minutes"), .remind(minutes: 1440, text: ""))
    }
    func testContinuousWorkAndRealBreakReset() {
        var work = VigilWorkContinuity()
        for _ in 0..<599 { XCTAssertFalse(work.advance(seconds: 5, idle: 0, available: true, minutes: 50)) }
        XCTAssertTrue(work.advance(seconds: 5, idle: 0, available: true, minutes: 50))
        XCTAssertEqual(work.elapsed, 0)
        _ = work.advance(seconds: 30, idle: 0, available: true, minutes: 50)
        XCTAssertFalse(work.advance(seconds: 5, idle: 300, available: true, minutes: 50))
        XCTAssertEqual(work.elapsed, 0)
        _ = work.advance(seconds: 30, idle: 0, available: true, minutes: 50)
        XCTAssertFalse(work.advance(seconds: 600, idle: 0, available: true, minutes: 50))
        XCTAssertEqual(work.elapsed, 0)
        XCTAssertFalse(work.advance(seconds: 5, idle: 0, available: false, minutes: 50))
    }
    func testMeetingBoundaryAndNoLateWarning() {
        let now = Date(timeIntervalSince1970: 10000)
        XCTAssertTrue(VigilMeetingPolicy.warningDue(start: now.addingTimeInterval(300), now: now))
        XCTAssertFalse(VigilMeetingPolicy.warningDue(start: now.addingTimeInterval(301), now: now))
        XCTAssertFalse(VigilMeetingPolicy.warningDue(start: now, now: now))
        XCTAssertFalse(VigilMeetingPolicy.warningDue(start: now.addingTimeInterval(-1), now: now))
    }
    func testReminderRoundTripKeepsStableIdentityAndDueTime() throws {
        let reminder = VigilReminder(due: Date(timeIntervalSince1970: 10000), text: "  Send draft  ")
        let restored = try JSONDecoder().decode(VigilReminder.self, from: JSONEncoder().encode(reminder))
        XCTAssertEqual(reminder, restored)
        XCTAssertEqual(restored.line, "Reminder: Send draft")
        XCTAssertEqual(restored.notificationID, reminder.notificationID)
        XCTAssertEqual(VigilReminder(due: Date(), text: "").line, "Your reminder is due.")
    }
}
