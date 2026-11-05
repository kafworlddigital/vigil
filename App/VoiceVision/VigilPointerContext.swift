#if VIGIL_VOICE_VISION && os(macOS)
import AppKit
import ApplicationServices
import ScreenCaptureKit

struct VigilPointerContext {
    var text: String
    var image: Data?
    var application: String

    @MainActor static func read() async throws -> Self {
        try check()
        guard AXIsProcessTrusted() else { throw ContextFailure.accessibility }
        let point = CGEvent(source: nil)?.location ?? .zero
        var hovered: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hovered)
        if status == .success, let hovered {
            var pid: pid_t = 0; AXUIElementGetPid(hovered, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? "Unknown app"
            guard !["tuck", "1password", "keychain", "passwords"].contains(where: name.lowercased().contains) else { throw RouterError.privateScreen }
            func string(_ key: CFString) -> String? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(hovered, key, &value) == .success else { return nil }
                return value as? String
            }
            guard string(kAXSubroleAttribute as CFString) != kAXSecureTextFieldSubrole as String else { throw RouterError.privateScreen }
            let text = [kAXSelectedTextAttribute, kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .compactMap { string($0 as CFString) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            if !text.isEmpty { return Self(text: String(text.prefix(2500)), application: name) }
        }
        // A crop only; never capture the full display and discard it afterwards.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try WorkScreenGuard.shareable(content)
        guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).contains(point) }) else { throw RouterError.unavailable }
        let bounds = CGDisplayBounds(display.displayID)
        let crop = CGRect(x: point.x - bounds.minX - 240, y: point.y - bounds.minY - 160, width: 480, height: 320)
            .intersection(CGRect(origin: .zero, size: bounds.size))
        guard crop.width > 0, crop.height > 0 else { throw RouterError.unavailable }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = crop
        configuration.width = Int(crop.width); configuration.height = Int(crop.height)
        configuration.showsCursor = false; configuration.capturesAudio = false
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }, exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try check()
        guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { throw RouterError.unavailable }
        return Self(text: "Small crop around the pointer", image: jpeg, application: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Screen")
    }
    @MainActor static func check() throws {
        try WorkScreenGuard.check()
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let vaults = ["tuck", "1password", "keychain access", "passwords", "bitwarden"]
        if windows.contains(where: { window in
            let owner = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            return vaults.contains(where: owner.contains)
        }) { throw RouterError.privateScreen }
    }
    enum ContextFailure: Error { case accessibility }
}
#endif
