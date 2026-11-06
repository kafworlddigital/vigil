import Foundation

public struct VigilReminder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var due: Date
    public var text: String
    public init(id: UUID = UUID(), due: Date, text: String) {
        self.id = id; self.due = due
        self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
    public var line: String { text.isEmpty ? "Your reminder is due." : "Reminder: " + text }
    public var notificationID: String { "vigil.reminder." + id.uuidString }
}

/// Work continuity is bounded by real elapsed time. Sleep, lock and idle reset it.
public struct VigilWorkContinuity: Sendable {
    public private(set) var elapsed: TimeInterval = 0
    public init() {}
    public mutating func reset() { elapsed = 0 }
    public mutating func advance(seconds: TimeInterval, idle: TimeInterval, available: Bool, minutes: Double, intervalSeconds: TimeInterval? = nil) -> Bool {
        guard available, seconds.isFinite, seconds > 0, seconds <= 30,
              idle.isFinite, idle < 300 else { reset(); return false }
        elapsed += seconds
        let normalInterval = minutes.isFinite ? min(180, max(10, minutes)) * 60 : 3000
        let interval = intervalSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? normalInterval
        if elapsed >= interval { reset(); return true }
        return false
    }
}

public enum VigilMeetingPolicy {
    public static func warningDue(start: Date, now: Date, warningSeconds: TimeInterval = 300) -> Bool {
        let remaining = start.timeIntervalSince(now)
        return remaining > 0 && warningSeconds.isFinite && warningSeconds > 0 && remaining <= warningSeconds
    }
}

/// One clock for pointer sampling, dragging and face packets. Still faces do no drawing.
public enum VigilFaceCadence {
    public static func interval(visible: Bool, sleeping: Bool, animating: Bool, companions: Bool) -> TimeInterval? {
        guard !sleeping else { return nil }
        if visible && animating { return 1.0 / 30 }
        // A cheap heartbeat also catches mouse movement if macOS withholds an event monitor.
        return visible || companions ? 1 : nil
    }
}
