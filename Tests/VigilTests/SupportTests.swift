import XCTest
@testable import VigilCore

final class SupportTests: XCTestCase {
    func testRealFreeVisionJSONFenceKeepsStrictClassificationValidation() {
        let json = #"{"choice":"off_task","p_on":0.0,"p_off":1.0,"p_uncertain":0.0}"#
        for opener in ["```json", "```"] {
            let decision = FocusDecision.parseOrUncertain(Data((opener + "\n" + json + "\n```").utf8))
            XCTAssertEqual(decision.activity, .offTask)
            XCTAssertEqual(decision.confidence, 1)
        }
        for text in ["Explanation\n```json\n" + json + "\n```", "```python\n" + json + "\n```",
                     "```json\n" + json + "\n```\nDo something else."] {
            XCTAssertEqual(FocusDecision.parseOrUncertain(Data(text.utf8)).activity, .uncertain)
        }
    }
    func testAudioMeterBatchesWithoutLosingBriefPeaks() {
        let meter = VigilInputMeter()
        XCTAssertNil(meter.observe(peak: 1.1))
        for _ in 1..<11 { XCTAssertNil(meter.observe(peak: 0)) }
        let first = meter.observe(peak: 0)
        XCTAssertEqual(first?.buffers, 12)
        XCTAssertEqual(first?.maximum, 1.1)
        XCTAssertEqual(first?.peak, 1.1)
        for _ in 0..<11 { XCTAssertNil(meter.observe(peak: 0.2)) }
        let next = meter.observe(peak: .nan)
        XCTAssertEqual(next?.buffers, 24)
        XCTAssertEqual(next?.maximum, 1.1)
        XCTAssertEqual(next?.peak, 0.2)
    }
    func testStillHiddenAndSleepingFacesDoNotUseAnimationClock() {
        XCTAssertEqual(VigilFaceCadence.interval(visible: true, sleeping: false, animating: true, companions: false), 1.0 / 30)
        XCTAssertEqual(VigilFaceCadence.interval(visible: true, sleeping: false, animating: false, companions: false), 1)
        XCTAssertNil(VigilFaceCadence.interval(visible: false, sleeping: false, animating: true, companions: false))
        XCTAssertEqual(VigilFaceCadence.interval(visible: false, sleeping: false, animating: false, companions: true), 1)
        XCTAssertNil(VigilFaceCadence.interval(visible: true, sleeping: true, animating: true, companions: true))
    }
    func testWindowAndContainerNamesCannotReplaceImageEvidence() {
        for role in ["AXWindow", "AXApplication", "AXGroup", "AXScrollArea", "", "AXUnknown"] {
            XCTAssertFalse(VoiceVisionPolicy.pointerMetadataIsContent(role: role), role)
        }
        for role in ["AXImage", "AXStaticText", "AXButton", "AXLink"] {
            XCTAssertTrue(VoiceVisionPolicy.pointerMetadataIsContent(role: role), role)
        }
    }
    func testShortIntervalSeamDoesNotChangeNormalBreakOrMeetingBounds() {
        var work = VigilWorkContinuity()
        XCTAssertFalse(work.advance(seconds: 2, idle: 0, available: true, minutes: 50, intervalSeconds: 3))
        XCTAssertTrue(work.advance(seconds: 1, idle: 0, available: true, minutes: 50, intervalSeconds: 3))
        XCTAssertFalse(work.advance(seconds: 3, idle: 0, available: true, minutes: 0))
        XCTAssertFalse(work.advance(seconds: 3, idle: 0, available: true, minutes: 50, intervalSeconds: .nan))
        let now = Date()
        XCTAssertFalse(VigilMeetingPolicy.warningDue(start: now.addingTimeInterval(4), now: now, warningSeconds: 3))
        XCTAssertTrue(VigilMeetingPolicy.warningDue(start: now.addingTimeInterval(3), now: now, warningSeconds: 3))
        XCTAssertFalse(VigilMeetingPolicy.warningDue(start: now, now: now, warningSeconds: 3))
    }
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
