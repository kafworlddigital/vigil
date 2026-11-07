import Foundation

public struct VigilSettings: Codable, Equatable, Sendable {
    public var interval: Double = 60
    public var allowPaidFallback = false
    public init() {}
    public var safeInterval: Double { interval.isFinite ? min(120, max(30, interval)) : 60 }
}
public struct ParkedIdea: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id; self.text = String(text.prefix(4000)); self.createdAt = createdAt
    }
}
public struct VigilState: Codable, Sendable {
    public var session: FocusSession?
    public var history: [FocusSession] = []
    public var ideas: [ParkedIdea] = []
    public var settings = VigilSettings()
    public var model = "No check yet"
    public var costUSD: Double = 0
    public var requestsToday = 0
    public var notice = "Ready when you are."
    public var revision = 0
    public var sentAt = Date()
    public init() {}
}
public struct VisibleWindow: Sendable {
    public var owner: String
    public var bundleID: String
    public var title: String
    public var readable: Bool
    public init(owner: String, bundleID: String = "", title: String = "", readable: Bool = true) {
        self.owner = owner; self.bundleID = bundleID; self.title = title; self.readable = readable
    }
}
public enum PrivacyGuard {
    public static let displayList = ["QuickTime Player (work capture card)", "Microsoft Teams", "Outlook", "Remote Desktop / Windows App", "Chrome Remote Desktop", "Any window titled QualityAI"]
    public static func isPrivate(_ windows: [VisibleWindow]) -> Bool {
        windows.contains { w in
            if !w.readable { return true }
            let app = (w.owner + " " + w.bundleID).lowercased()
            let title = w.title.lowercased().replacingOccurrences(of: " ", with: "")
            return ["quicktime", "microsoft teams", "msteams", "com.microsoft.teams", "outlook", "remote desktop", "remotedesktop", "windows app", "com.microsoft.rdc", "com.microsoft.windowsapp"].contains(where: app.contains)
                || title.contains("qualityai") || title.contains("remotedesktop")
                || title.contains("remotedesktop.google.com")
        }
    }
}
public struct DailySummary: Sendable {
    public var focusMinutes: Int
    public var driftCount: Int
    public var parkedCount: Int
    public init(sessions: [FocusSession], ideas: [ParkedIdea], now: Date = Date()) {
        let calendar = Calendar.current
        // Attribute each observation to its actual day, never count skipped/uncertain time as focus.
        let checks = sessions.flatMap { s in s.checks.map { (s.startedAt.addingTimeInterval($0.elapsed), $0) } }
            .filter { calendar.isDate($0.0, inSameDayAs: now) }
        focusMinutes = Int(checks.filter { $0.1.activity == .onTask }.reduce(0) { $0 + ($1.1.sampleDuration ?? 60) } / 60)
        driftCount = checks.filter { $0.1.nudged }.count
        parkedCount = ideas.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }.count
    }
}
/// File operations are serialised by the owner; atomic replacement preserves the existing Markdown.
public final class ParkingLotWriter {
    public let url: URL
    public let header: String
    public init(url: URL, header: String = "Drifter-in-chief · Review on Sundays") { self.url = url; self.header = header }
    public func append(_ idea: ParkedIdea) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let exists = manager.fileExists(atPath: url.path)
        var previous = exists ? try String(contentsOf: url, encoding: .utf8) : "# Vigil · Parking Lot\n\n\(header)\n"
        // Stable id makes retry after a failed cloud append idempotent.
        let marker = "<!-- vigil:\(idea.id.uuidString) -->"
        guard !previous.contains(marker) else { return }
        let stamp = ISO8601DateFormatter().string(from: idea.createdAt)
        let text = idea.text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        previous += "\n- \(stamp) — \(text) \(marker)\n"
        try Data(previous.utf8).write(to: url, options: .atomic)
    }
}
public struct FocusMilestones {
    private var continuous: Double = 0
    private var reminded: Set<String> = []
    public init() {}
    public mutating func resetContinuity() { continuous = 0 }
    public mutating func advance(_ seconds: Double) -> Bool {
        guard seconds.isFinite, seconds > 0 else { return false }
        continuous += seconds
        if continuous >= 50 * 60 { continuous = 0; return true }
        return false
    }
    public mutating func meetingDue(id: String, start: Date, now: Date) -> Bool {
        guard start > now, start.timeIntervalSince(now) <= 600, !reminded.contains(id) else { return false }
        reminded.insert(id); return true
    }
}
