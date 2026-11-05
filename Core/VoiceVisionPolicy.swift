import Foundation

/// Pure policy shared by the native UI and regression tests. No capture or networking.
public enum VigilNudgeStyle: String, CaseIterable, Codable {
    case chime, bounce, colourFlash, eyeWiggle, spokenLine
    public var title: String {
        switch self {
        case .chime: return "Chime"
        case .bounce: return "Bounce"
        case .colourFlash: return "Colour flash"
        case .eyeWiggle: return "Eye wiggle"
        case .spokenLine: return "Spoken line"
        }
    }
}

public enum VigilVoiceCommand: Equatable, Sendable {
    case whatIsThis(String)
    case lookAtMe(String)

    public static func parse(_ transcript: String) -> Self? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.first == "vigil" else { return nil }
        let rest = Array(words.dropFirst())
        if rest.starts(with: ["what", "is", "this"]) {
            return .whatIsThis(rest.dropFirst(3).joined(separator: " "))
        }
        if rest.starts(with: ["look", "at", "me"]) {
            return .lookAtMe(rest.dropFirst(3).joined(separator: " "))
        }
        return nil
    }
}

public enum VoiceVisionPolicy {
    public static let shortLines = ["Back to it.", "Focus.", "One thing."]
    public static let unavailable = "I couldn't get a clear answer just now."
    public static func volume(_ value: Double) -> Float {
        Float(value.isFinite ? min(1, max(0, value)) : 0.5)
    }
    /// One bounded sentence for both speech and the face bubble, including malformed replies.
    public static func sentence(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"*`")))
        guard !clean.isEmpty, !clean.hasPrefix("{"), !clean.hasPrefix("[") else { return unavailable }
        let sentence = clean.prefix { !".!?".contains($0) }
        let words = sentence.split(whereSeparator: \.isWhitespace).prefix(24).joined(separator: " ")
        guard !words.isEmpty else { return unavailable }
        return String(words.prefix(180)) + "."
    }
}
