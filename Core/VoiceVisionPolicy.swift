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
    case stuck(String)
    case remind(minutes: Int, text: String)

    /// Only the first, separate word can wake Vigil. Keep phonetic tolerance bounded.
    public static func hasWakeWord(_ transcript: String) -> Bool {
        guard let word = transcript.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first else { return false }
        if ["vigil", "virgil", "vigils", "vigel", "vidjil", "visual", "rachel"].contains(String(word)) { return true }
        guard word.first == "v", (4...6).contains(word.count) else { return false }
        let target = Array("vigil"), candidate = Array(word)
        var row = Array(0...target.count)
        for (i, letter) in candidate.enumerated() {
            var next = [i + 1]
            for (j, wanted) in target.enumerated() {
                next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (letter == wanted ? 0 : 1)))
            }
            row = next
        }
        return row[target.count] <= 1
    }

    public static func parse(_ transcript: String, requiresWakeWord: Bool = true) -> Self? {
        if !requiresWakeWord && !hasWakeWord(transcript) { return parse("Vigil " + transcript) }
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard hasWakeWord(transcript) else { return nil }
        let rest = Array(words.dropFirst())
        if rest.starts(with: ["what", "is", "this"]) {
            return .whatIsThis(rest.dropFirst(3).joined(separator: " "))
        }
        if rest.starts(with: ["look", "at", "me"]) {
            return .lookAtMe(rest.dropFirst(3).joined(separator: " "))
        }
        if rest.starts(with: ["i", "m", "stuck"]) || rest.starts(with: ["im", "stuck"]) || rest.starts(with: ["i", "am", "stuck"]) {
            return .stuck("")
        }
        if rest.starts(with: ["remind", "me", "in"]),
           transcript.range(of: #"\bin\s*[-−]|\bin\s*\d+[.,]\d+"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if rest.starts(with: ["remind", "me", "in"]), let unit = rest.firstIndex(where: { $0 == "minute" || $0 == "minutes" }) {
            let number = Array(rest[3..<unit])
            let small = ["one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60]
            let minutes: Int?
            if number.count == 1 { minutes = Int(number[0]) ?? small[number[0]] }
            else if number.count == 2, let tens = small[number[0]], tens >= 20, tens.isMultiple(of: 10), let ones = small[number[1]], ones < 10 { minutes = tens + ones }
            else { minutes = nil }
            guard let minutes, (1...1440).contains(minutes) else { return nil }
            var text = Array(rest.dropFirst(unit + 1))
            if text.first == "to" { text.removeFirst() }
            return .remind(minutes: minutes, text: String(text.joined(separator: " ").prefix(300)))
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
