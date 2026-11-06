#if VIGIL_VOICE_VISION
import SwiftUI
import EventKit
import UserNotifications
import AVFoundation
#if os(macOS)
import AppKit
#endif

@MainActor final class VigilSupportController: ObservableObject {
    static let shared = VigilSupportController()
    @Published private(set) var reminders: [VigilReminder] = []
    @Published var calendarMessage = "Calendar access is requested when you enable meeting warnings."
    @Published var tiredMessage = "Tired check is off. No camera use."
    @Published private(set) var coverOpen = false
    @Published private(set) var checkingFrame = false
    var currentTask = ""
    private let store = EKEventStore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var foreground = true
    private var sleeping = false
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var continuity = VigilWorkContinuity()
    private var calendarAt = Date.distantPast
    private var tiredAt = Date.distantPast
    private var suggestionAt = Date.distantPast
    private var warned: [String: Date] = [:]
    private var camera: VigilTiredFrame?
    private var frameTask: Task<Void, Never>?
    private var cues = 0
    private var notificationTask: Task<Void, Never>?
    private var pendingAnnouncements: [String] = []
    private var reminderFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vigil/voice-reminders.json")
    }
    func isEnabled(_ name: String) -> Bool {
        UserDefaults.standard.object(forKey: "vigil.support." + name) as? Bool ?? ["stuck", "reminders", "break"].contains(name)
    }
    func start() {
        guard !VigilEdition.macy, !VoiceVisionController.proofMode, timer == nil else { return }
        if let data = try? Data(contentsOf: reminderFile), let saved = try? JSONDecoder().decode([VigilReminder].self, from: data) {
            reminders = saved
        }
        if !isEnabled("reminders") { cancelAllReminders() }
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        #if os(macOS)
        let centre = NSWorkspace.shared.notificationCenter
        observers.append(centre.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.resetBreak(); self?.setCoverOpen(false) }
        })
        observers.append(centre.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.resetBreak(); self?.calendarAt = .distantPast }
        })
        #endif
    }
    func setForeground(_ active: Bool) {
        foreground = active; resetBreak()
        if !active { setCoverOpen(false) }
    }
    func resetBreak() { continuity.reset(); lastTick = ProcessInfo.processInfo.systemUptime }
    func changed(_ name: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "vigil.support." + name)
        if name == "reminders", !enabled { cancelAllReminders() }
        if name == "break" { resetBreak() }
        if name == "tired", !enabled { setCoverOpen(false) }
        if name == "meeting" {
            if enabled { Task { await requestCalendarOnce() } }
            else { calendarMessage = "Meeting warnings are off." }
        }
    }
    func requestCalendarOnce() async {
        guard !VoiceVisionController.proofMode else { return }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined { _ = try? await store.requestFullAccessToEvents() }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            calendarMessage = "Calendar access is off. Change it in system Settings if you want warnings."; return
        }
        calendarMessage = "Five-minute warnings are on while Vigil runs. Calendar titles stay on-device."
        calendarAt = .distantPast
    }
    func addReminder(minutes: Int, text: String) {
        start()
        guard isEnabled("reminders"), (1...1440).contains(minutes) else {
            VoiceVisionController.shared.announce("Switch on voice reminders in Settings."); return
        }
        guard reminders.count < 50 else {
            VoiceVisionController.shared.announce("You have 50 reminders. Cancel one in Settings first."); return
        }
        let reminder = VigilReminder(due: Date().addingTimeInterval(Double(minutes) * 60), text: text)
        reminders.append(reminder); reminders.sort { $0.due < $1.due }; save()
        notificationTask?.cancel()
        // Reconcile all pending reminders after permission resolves, so quick consecutive requests are preserved.
        notificationTask = Task { @MainActor [weak self] in
            guard VigilAI.shared.notifications else { return }
            let centre = UNUserNotificationCenter.current()
            let settings = await centre.notificationSettings()
            if settings.authorizationStatus == .notDetermined { _ = try? await centre.requestAuthorization(options: [.alert, .sound]) }
            guard let self, !Task.isCancelled, self.isEnabled("reminders"), VigilAI.shared.notifications else { return }
            for pending in self.reminders where pending.due > Date() {
                let content = UNMutableNotificationContent(); content.title = "Vigil reminder"; content.body = pending.line
                if VigilVoiceOutput.shared.enabled { content.sound = .default }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, pending.due.timeIntervalSinceNow), repeats: false)
                try? await centre.add(UNNotificationRequest(identifier: pending.notificationID, content: content, trigger: trigger))
                if Task.isCancelled || !self.reminders.contains(where: { $0.id == pending.id }) || !self.isEnabled("reminders") {
                    centre.removePendingNotificationRequests(withIdentifiers: [pending.notificationID])
                }
            }
        }
        VoiceVisionController.shared.announce("I’ll remind you in \(minutes) \(minutes == 1 ? "minute" : "minutes").")
    }
    func cancelReminder(_ id: UUID) {
        let removed = reminders.filter { $0.id == id }
        reminders.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: removed.map(\.notificationID)); save()
    }
    private func cancelAllReminders() {
        notificationTask?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminders.map(\.notificationID))
        reminders = []; save()
    }
    private func save() {
        try? FileManager.default.createDirectory(at: reminderFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(reminders) {
            try? data.write(to: reminderFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reminderFile.path)
        }
    }
    func setCoverOpen(_ value: Bool) {
        guard !VoiceVisionController.proofMode else { return }
        coverOpen = value && isEnabled("tired") && foreground && !sleeping
        if !coverOpen {
            frameTask?.cancel(); camera?.cancel(); camera = nil; cues = 0
            tiredMessage = "Camera checks paused. No frame is saved or uploaded."
        } else {
            tiredAt = .distantPast
            Task { @MainActor in
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
                if AVCaptureDevice.authorizationStatus(for: .video) != .authorized { self.setCoverOpen(false); self.tiredMessage = "Camera permission is off. Change it in system Settings." }
            }
        }
    }
    func pauseCamera() async {
        frameTask?.cancel(); camera?.cancel()
        await frameTask?.value
        camera = nil
    }
    func tryTiredCheck() {
        guard !checkingFrame, !VoiceVisionController.shared.busy else { return }
        frameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.checkingFrame = false; self.frameTask = nil; self.camera = nil }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                self.tiredMessage = "Allow Camera in macOS Settings for a tired check."; VoiceVisionController.shared.announce(self.tiredMessage, speak: false); return
            }
            self.checkingFrame = true; self.tiredMessage = "Camera on briefly · one local frame"
            let sampler = VigilTiredFrame(); self.camera = sampler
            do {
                let result = try await sampler.check(); try Task.checkCancellation()
                self.tiredMessage = result == .covered ? "Camera off · dark or covered frame skipped." : "Camera off · local check complete. Nothing saved or sent."
                VoiceVisionController.shared.announce(self.tiredMessage, speak: false)
            } catch { self.tiredMessage = "Camera off · check unavailable. Nothing saved or sent." }
        }
    }
    private func tick() {
        guard !VoiceVisionController.proofMode, !VigilEdition.macy else { return }
        let uptime = ProcessInfo.processInfo.systemUptime, delta = uptime - lastTick; lastTick = uptime
        var available = foreground && !sleeping
        var idle: Double = 0
        #if os(macOS)
        let console = CGSessionCopyCurrentDictionary() as? [String: Any]
        available = available && console?["CGSSessionScreenIsLocked"] as? Bool != true && console?["kCGSessionOnConsoleKey"] as? Bool != false
        idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        #endif
        if !available { resetBreak(); setCoverOpen(false); return }
        let now = Date()
        if isEnabled("reminders") {
            let due = reminders.filter { $0.due <= now }
            if !due.isEmpty {
                let ids = Set(due.map(\.id)); reminders.removeAll { ids.contains($0.id) }; save()
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: due.map(\.notificationID))
                for reminder in due {
                    if now.timeIntervalSince(reminder.due) < 900 { enqueue(reminder.line) }
                    else { VoiceVisionController.shared.announce("Missed reminder: " + reminder.text, speak: false) }
                }
            }
        }
        if isEnabled("break") {
            let minutes = UserDefaults.standard.object(forKey: "vigil.support.breakMinutes") as? Double ?? 50
            if continuity.advance(seconds: delta, idle: idle, available: available, minutes: minutes) { enqueue("Stand up. Drink water.") }
        } else { continuity.reset() }
        if isEnabled("meeting"), now.timeIntervalSince(calendarAt) >= 20 { calendarAt = now; checkMeetings(now: now) }
        if coverOpen, isEnabled("tired"), now.timeIntervalSince(tiredAt) >= 300, frameTask == nil,
           !VoiceVisionController.shared.busy, !VigilVoiceOutput.shared.speaking,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized { checkTired(now: now) }
        if !pendingAnnouncements.isEmpty, !VoiceVisionController.shared.busy, !VigilVoiceOutput.shared.speaking {
            VoiceVisionController.shared.announce(pendingAnnouncements.removeFirst())
        }
    }
    private func enqueue(_ text: String) { if pendingAnnouncements.count < 50 { pendingAnnouncements.append(text) } }
    private func checkMeetings(now: Date) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        warned = warned.filter { $0.value > now.addingTimeInterval(-86400) }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(301), calendars: nil)
        for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate }) {
            guard !event.isAllDay, event.status != .canceled,
                  !(event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) ?? false),
                  VigilMeetingPolicy.warningDue(start: event.startDate, now: now) else { continue }
            let id = (event.calendarItemIdentifier) + ":" + String(event.startDate.timeIntervalSince1970)
            guard warned[id] == nil else { continue }
            warned[id] = now
            enqueue("Meeting in 5 minutes: " + String((event.title ?? "Your meeting").prefix(160)))
        }
    }
    private func checkTired(now: Date) {
        tiredAt = now; checkingFrame = true; tiredMessage = "Camera on briefly · one on-device frame"
        let sampler = VigilTiredFrame(); camera = sampler
        frameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.checkingFrame = false; self.frameTask = nil; self.camera = nil }
            do {
                let result = try await sampler.check()
                guard !Task.isCancelled, self.coverOpen, self.isEnabled("tired"), self.foreground else { return }
                switch result {
                case .covered: self.cues = 0; self.setCoverOpen(false); self.tiredMessage = "Dark or covered frame skipped. Confirm the cover is open before restarting."
                case .clear: self.cues = 0; self.tiredMessage = "Camera off · single-frame check complete; nothing stored."
                case .cue:
                    self.cues += 1; self.tiredMessage = "Camera off · a possible break cue; nothing stored."
                    if self.cues >= 2, now.timeIntervalSince(self.suggestionAt) >= 1800 {
                        self.cues = 0; self.suggestionAt = now; self.enqueue("A short break might help. Stand up and rest your eyes.")
                    }
                }
            } catch {
                if !Task.isCancelled { self.tiredMessage = "Camera check unavailable. No frame was saved or sent." }
            }
        }
    }
}

struct VigilSupportSettings: View {
    @ObservedObject private var support = VigilSupportController.shared
    @AppStorage("vigil.support.stuck") private var stuck = true
    @AppStorage("vigil.support.reminders") private var reminders = true
    @AppStorage("vigil.support.meeting") private var meeting = false
    @AppStorage("vigil.support.break") private var breaks = true
    @AppStorage("vigil.support.tired") private var tired = false
    @AppStorage("vigil.support.breakMinutes") private var breakMinutes = 50.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider(); Text("Small steps and reminders").font(.headline)
            Toggle("Next-step help · ‘Vigil, I’m stuck’", isOn: $stuck).onChange(of: stuck) { _, value in support.changed("stuck", enabled: value) }
            Toggle("Voice reminders", isOn: $reminders).onChange(of: reminders) { _, value in support.changed("reminders", enabled: value) }
            Text("Type or say ‘Vigil, remind me in 10 minutes to stretch’. Speech needs Vigil running; notifications can arrive while closed.").font(.caption).foregroundStyle(.secondary)
            ForEach(support.reminders) { reminder in
                HStack {
                    VStack(alignment: .leading) { Text(reminder.text.isEmpty ? "Reminder" : reminder.text); Text(reminder.due, style: .time).font(.caption) }
                    Spacer(); Button("Cancel") { support.cancelReminder(reminder.id) }
                }
            }
            Toggle("Meeting warning · 5 minutes before", isOn: $meeting).onChange(of: meeting) { _, value in support.changed("meeting", enabled: value) }
            Text(support.calendarMessage).font(.caption).foregroundStyle(.secondary)
            Toggle("Break nudge · stand up and drink water", isOn: $breaks).onChange(of: breaks) { _, value in support.changed("break", enabled: value) }
            Stepper("After \(Int(breakMinutes)) minutes of work", value: $breakMinutes, in: 10...180, step: 5).disabled(!breaks)
            Button("I took a break") { support.resetBreak() }
            Text("Work time, not a sitting sensor. Five minutes idle or sleep resets it; iPhone/iPad count only time with Vigil active.").font(.caption).foregroundStyle(.secondary)
            Divider(); Toggle("Tired check · Apple Vision on-device", isOn: $tired).onChange(of: tired) { _, value in support.changed("tired", enabled: value) }
            Toggle("Camera cover is open for this run", isOn: Binding(get: { support.coverOpen }, set: support.setCoverOpen)).disabled(!tired)
            Label(support.tiredMessage, systemImage: support.checkingFrame ? "camera.fill" : "camera").font(.caption).foregroundStyle(support.checkingFrame ? .primary : .secondary)
            Text("One frame every five minutes, never stored or uploaded. No microphone. A cover cannot be sensed reliably: close this control when closing it. Darkness is skipped. Cues are fallible. Backgrounding, sleep or lock clears cover confirmation.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
