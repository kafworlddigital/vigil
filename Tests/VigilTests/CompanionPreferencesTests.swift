import XCTest
@testable import VigilCore

final class CompanionPreferencesTests:XCTestCase {
    func testLiveChoicesSurviveReopeningAndAreIsolatedBetweenEditions() throws {
        let keithName="vigil-test-keith-"+UUID().uuidString,macyName="vigil-test-macy-"+UUID().uuidString
        let keith=try XCTUnwrap(UserDefaults(suiteName:keithName)),macy=try XCTUnwrap(UserDefaults(suiteName:macyName))
        defer{keith.removePersistentDomain(forName:keithName);macy.removePersistentDomain(forName:macyName)}
        let p=CompanionPreferences(defaults:keith)
        XCTAssertEqual(p.name,"Vigil");XCTAssertEqual(p.colour,.blueberry);XCTAssertEqual(p.corner,.bottomRight)
        p.name="  Pip  ";p.colour = .mint;p.nudge = .quiet;p.corner = .topLeft
        let reopened=CompanionPreferences(defaults:try XCTUnwrap(UserDefaults(suiteName:keithName)))
        XCTAssertEqual(reopened.name,"Pip");XCTAssertEqual(reopened.colour,.mint)
        XCTAssertEqual(reopened.nudge,.quiet);XCTAssertEqual(reopened.corner,.topLeft)
        let other=CompanionPreferences(defaults:macy)
        XCTAssertEqual(other.name,"Vigil");XCTAssertEqual(other.nudge,.gentle)
        XCTAssertEqual(other.colour,.blueberry);XCTAssertEqual(other.corner,.bottomRight)
    }
    func testInvalidSavedChoicesAndEmptyNameHaveSafeDefaults() throws {
        let suite="vigil-test-invalid-"+UUID().uuidString
        let d=try XCTUnwrap(UserDefaults(suiteName:suite));defer{d.removePersistentDomain(forName:suite)}
        for key in [CompanionPreferences.colourKey,CompanionPreferences.cornerKey,CompanionPreferences.nudgeKey]{d.set("unknown",forKey:key)}
        let p=CompanionPreferences(defaults:d);p.name=" \n "
        XCTAssertEqual(p.name,"Vigil");XCTAssertEqual(p.corner,.bottomRight);XCTAssertEqual(p.nudge,.gentle)
        XCTAssertEqual(p.colour.colours,[0xA9BCFF,0x6C86F5,0x4254D6,0x2B2F8F])
        p.name=String(repeating:"a",count:80);XCTAssertEqual(p.name.count,24)
        XCTAssertEqual(Set(CompanionColour.allCases.map{$0.colours}).count,6)
    }
}
