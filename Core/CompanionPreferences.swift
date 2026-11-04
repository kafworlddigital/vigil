import Foundation

/// Device-local and edition-local; never changes a contact, session or credential.
public enum CompanionColour:String,CaseIterable,Codable {
    case blueberry,lavender,rose,peach,mint,sky
    public var title:String { rawValue.capitalized }
    public var colours:[UInt32] {
        switch self {
        case .blueberry:return [0xA9BCFF,0x6C86F5,0x4254D6,0x2B2F8F]
        case .lavender:return [0xDBCCFF,0xB495ED,0x8A64C7,0x593991]
        case .rose:return [0xFFD1E2,0xF29DC1,0xCF669B,0x8D3F70]
        case .peach:return [0xFFE0BD,0xF5BA85,0xD98D61,0x98503F]
        case .mint:return [0xBEEBDD,0x7BC8B1,0x3D9A8F,0x27646C]
        case .sky:return [0xBFE8FF,0x7CC5EB,0x428FBE,0x315C8B]
        }
    }
}
public enum CompanionCorner:String,CaseIterable,Codable {
    case topLeft,topRight,bottomLeft,bottomRight
    public var title:String {
        switch self {case .topLeft:return "Top left";case .topRight:return "Top right";case .bottomLeft:return "Bottom left";case .bottomRight:return "Bottom right"}
    }
    public var left:Bool { self == .topLeft || self == .bottomLeft }
    public var top:Bool { self == .topLeft || self == .topRight }
}
public enum CompanionNudge:String,CaseIterable,Codable {
    case gentle,firm,quiet
    public var title:String {rawValue.capitalized}
    public var example:String {
        switch self {case .gentle:return "Ready for one small step?";case .firm:return "Back to your task. One step now.";case .quiet:return "A quiet hint. No notification."}
    }
}
public struct CompanionPreferences {
    public static let nameKey="vigil.companion.name"
    public static let colourKey="vigil.companion.colour"
    public static let nudgeKey="vigil.companion.nudge"
    public static let cornerKey="vigil.companion.corner"
    public let defaults:UserDefaults
    public init(defaults:UserDefaults = .standard){self.defaults=defaults}
    public var name:String {
        get {let v=(defaults.string(forKey:Self.nameKey) ?? "").trimmingCharacters(in:.whitespacesAndNewlines);return v.isEmpty ? "Vigil":String(v.prefix(24))}
        nonmutating set {defaults.set(String(newValue.prefix(24)),forKey:Self.nameKey)}
    }
    public var colour:CompanionColour {
        get {CompanionColour(rawValue:defaults.string(forKey:Self.colourKey) ?? "") ?? .blueberry}
        nonmutating set {defaults.set(newValue.rawValue,forKey:Self.colourKey)}
    }
    public var nudge:CompanionNudge {
        get {CompanionNudge(rawValue:defaults.string(forKey:Self.nudgeKey) ?? "") ?? .gentle}
        nonmutating set {defaults.set(newValue.rawValue,forKey:Self.nudgeKey)}
    }
    public var corner:CompanionCorner {
        get {CompanionCorner(rawValue:defaults.string(forKey:Self.cornerKey) ?? "") ?? .bottomRight}
        nonmutating set {defaults.set(newValue.rawValue,forKey:Self.cornerKey)}
    }
}
