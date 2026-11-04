#if os(macOS)
import AppKit
import SwiftUI
import ScreenCaptureKit
import Vision
import EventKit

/// Metadata only. Never asks ScreenCaptureKit for pixels until all visible windows pass.
enum WorkScreenGuard {
    static func check() throws {
        guard CGPreflightScreenCaptureAccess(),
              let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { throw RouterError.privateScreen }
        let visible=windows.compactMap { w -> VisibleWindow? in
            guard let owner=w[kCGWindowOwnerName as String] as? String else { return VisibleWindow(owner:"",title:"QualityAI — unknown window metadata") }
            let pid=w[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bundle=NSRunningApplication(processIdentifier:pid)?.bundleIdentifier ?? ""
            let title=w[kCGWindowName as String] as? String
            let layer=w[kCGWindowLayer as String] as? Int ?? 0
            let readable=title != nil || layer != 0 || pid==ProcessInfo.processInfo.processIdentifier
            return VisibleWindow(owner:owner,bundleID:bundle,title:title ?? "",readable:readable)
        }
        guard !PrivacyGuard.isPrivate(visible) else { throw RouterError.privateScreen }
    }
    static func shareable(_ content:SCShareableContent) throws {
        let windows=content.windows.compactMap { w -> VisibleWindow? in
            guard w.isOnScreen, let app=w.owningApplication else { return nil }
            return VisibleWindow(owner:app.applicationName,bundleID:app.bundleIdentifier,title:w.title ?? "",readable:w.title != nil || w.windowLayer != 0 || app.processID==ProcessInfo.processInfo.processIdentifier)
        }
        guard !PrivacyGuard.isPrivate(windows) else { throw RouterError.privateScreen }
    }
}
struct VigilScreen {
    let jpeg:Data
    let ocr:String
    let app:String
    @MainActor static func capture() async throws -> VigilScreen {
        try WorkScreenGuard.check()
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        try WorkScreenGuard.shareable(content)
        try WorkScreenGuard.check()
        guard let display=content.displays.first(where:{$0.displayID==CGMainDisplayID()}) else { throw RouterError.unavailable }
        let own=content.applications.filter{$0.processID==ProcessInfo.processInfo.processIdentifier || PrivacyGuard.isPrivate([VisibleWindow(owner:$0.applicationName,bundleID:$0.bundleIdentifier)])}
        let filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config=SCStreamConfiguration()
        let scale=min(1,1100.0/Double(max(display.width,display.height)))
        config.width=max(1,Int(Double(display.width)*scale));config.height=max(1,Int(Double(display.height)*scale))
        config.showsCursor=false;config.capturesAudio=false
        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        try WorkScreenGuard.check() // Discard immediately if a private window appeared during capture.
        let latest=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        try WorkScreenGuard.shareable(latest)
        let recognize=VNRecognizeTextRequest();recognize.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage:image).perform([recognize])
        let text=(recognize.results ?? []).prefix(140).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
        try WorkScreenGuard.check()
        let rep=NSBitmapImageRep(cgImage:image)
        guard let jpeg=rep.representation(using:.jpeg,properties:[.compressionFactor:0.65]) else { throw RouterError.unavailable }
        return VigilScreen(jpeg:jpeg,ocr:text,app:NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")
    }
}
// Point at the freshly rechecked foreground window; never invent a model-selected UI target.
enum VigilPointing {
    @MainActor static func currentWindow()->CGPoint? {
        guard (try? WorkScreenGuard.check()) != nil,let pid=NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else{return nil}
        let display=CGDisplayBounds(CGMainDisplayID())
        for window in list where (window[kCGWindowOwnerPID as String] as? pid_t)==pid && (window[kCGWindowLayer as String] as? Int)==0 {
            guard let raw=window[kCGWindowBounds as String] as? [String:Any],let rect=CGRect(dictionaryRepresentation:raw as CFDictionary),rect.width>120,rect.height>100 else{continue}
            let target=CGPoint(x:rect.midX,y:rect.minY+40)
            guard display.contains(target) else{return nil}
            return CGPoint(x:target.x-display.minX,y:target.y-display.minY)
        }
        return nil
    }
}
@MainActor final class MacFocusEngine:ObservableObject {
    @Published var state=VigilState()
    @Published var settings=VigilSettings()
    @Published var error=""
    var onBroadcast:((Packet)->Void)?
    private let folder:URL
    private let file:URL
    private let router:OpenRouterClient
    private var timer:Timer?
    private var task:Task<Void,Never>?
    private var generation=UUID()
    private var lastTick=ProcessInfo.processInfo.systemUptime
    private var lastCheck:Double=0
    private var policy=FocusNudgePolicy(maximumGap:90)
    private var milestones=FocusMilestones()
    private var pendingIdeas:[UUID]=[]
    private let events=EKEventStore()
    private var nextMeeting:(id:String,start:Date)?
    private var observers:[NSObjectProtocol]=[]
    private let nudgePanel=VigilNudgePanel()
    init() {
        folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Vigil",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        file=folder.appendingPathComponent("state.json")
        router=OpenRouterClient(cacheURL:folder.appendingPathComponent("models.json"),usageURL:folder.appendingPathComponent("usage.json"))
        if let saved=try? Data(contentsOf:file),let decoded=try? JSONDecoder().decode(VigilState.self,from:saved) {
            state=decoded;settings=decoded.settings
            if var interrupted=state.session,interrupted.status != .ended {
                interrupted.end();interrupted.detail="Vigil closed. Start again when you're ready."
                state.history.removeAll{$0.id==interrupted.id};state.history.insert(interrupted,at:0);state.session=nil
            }
        }
        pendingIdeas=(try? Data(contentsOf:folder.appendingPathComponent("pending-ideas.json"))).flatMap{try? JSONDecoder().decode([UUID].self,from:$0)} ?? []
        _=KeyVault.importTuckIfAvailable()
        let nc=NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.pause()} })
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task{@MainActor in self?.tick()} }
        flushParkingLot();sync()
    }
    func setConnected(_ connected:Bool) { if connected { sync() } }
    func start(task:String,minutes:Double) {
        let clean=task.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { error="Choose one task first.";return }
        end();cancelWork()
        state.session=FocusSession(task:clean,duration:minutes*60)
        state.session?.configuredInterval=settings.safeInterval
        state.session?.detail="First check in \(Int(settings.safeInterval)) seconds"
        policy=FocusNudgePolicy(maximumGap:settings.safeInterval*1.5)
        milestones=FocusMilestones();lastCheck=0;lastTick=ProcessInfo.processInfo.systemUptime
        findMeeting();state.notice="One task. You've got company.";error="";sync()
    }
    func pause() {
        guard state.session?.status == .running else { return }
        cancelWork();state.session?.pause("Taking a moment. Resume when you're ready.")
        policy.reset();milestones.resetContinuity();sync()
    }
    func resume() {
        guard state.session?.status == .paused else { return }
        cancelWork();state.session?.resume();lastTick=ProcessInfo.processInfo.systemUptime
        lastCheck=state.session?.elapsed ?? 0;findMeeting();sync()
    }
    func end() {
        guard var session=state.session,session.status != .ended else { return }
        cancelWork();session.end();state.session=session
        state.history.removeAll{$0.id==session.id};state.history.insert(session,at:0)
        state.history=Array(state.history.prefix(365));sync()
    }
    func park(_ idea:String) {
        let clean=idea.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { error="What would you like to park?";return }
        parkRecord(ParkedIdea(text:clean))
    }
    private func parkRecord(_ incoming:ParkedIdea) {
        guard !state.ideas.contains(where:{$0.id==incoming.id}) else { return }
        let entry=ParkedIdea(id:incoming.id,text:incoming.text,createdAt:incoming.createdAt)
        guard !entry.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        state.ideas.append(entry);pendingIdeas.append(entry.id)
        savePending();sync();flushParkingLot()
        state.notice="Parked for Sunday, drifter-in-chief. Back to your task?"
        notify(state.notice);sync()
    }
    private func flushParkingLot() {
        // Only write to an existing iCloud Drive container. Never invent a local substitute cloud.
        let base=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs",isDirectory:true)
        guard FileManager.default.fileExists(atPath:base.path) else {
            if !pendingIdeas.isEmpty { state.notice="Idea saved here. iCloud copy will catch up when available." };return
        }
        let writer=ParkingLotWriter(url:base.appendingPathComponent("Vigil/Parking Lot.md"))
        for id in pendingIdeas {
            guard let idea=state.ideas.first(where:{$0.id==id}) else { continue }
            do { try writer.append(idea);pendingIdeas.removeAll{$0==id} }
            catch { state.notice="Idea saved here. iCloud copy is waiting.";break }
        }
        savePending()
    }
    private func savePending() { try? JSONEncoder().encode(pendingIdeas).write(to:folder.appendingPathComponent("pending-ideas.json"),options:.atomic) }
    func updateSettings(_ value:VigilSettings) {
        cancelWork();settings=value;settings.interval=value.safeInterval;state.settings=settings
        state.session?.configuredInterval=settings.safeInterval;lastCheck=state.session?.elapsed ?? 0
        policy=FocusNudgePolicy(maximumGap:settings.safeInterval*1.5);sync()
    }
    func receive(_ packet:Packet,reply:@escaping(Packet)->Void) {
        if packet.command=="faceMood",let text=packet.text,let mood=Mood(rawValue:text) { VigilCharacterHost.shared.setMood(mood);return }
        if packet.command=="faceRelease" { VigilCharacterHost.shared.releaseMood();return }
        switch packet.command {
        case "focusStart":
            let args=packet.text.flatMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]} ?? [:]
            start(task:args["task"] as? String ?? "",minutes:args["minutes"] as? Double ?? 30)
        case "focusPause":pause()
        case "focusResume":resume()
        case "focusEnd":end()
        case "focusPark":park(packet.text ?? "")
        case "focusParkRecord":if let text=packet.text,let record=try? JSONDecoder().decode(ParkedIdea.self,from:Data(text.utf8)){parkRecord(record)}
        case "focusSettings":if let text=packet.text,let s=try? JSONDecoder().decode(VigilSettings.self,from:Data(text.utf8)){updateSettings(s)}
        case "focusSync","focusPing":break
        default:return
        }
        if let text=encodedState() { reply(Packet(command:"focusState",callID:packet.callID,text:text)) }
    }
    func sync() {
        state.settings=settings;state.revision += 1;state.sentAt=Date()
        if let data=try? JSONEncoder().encode(state) {
            try? data.write(to:file,options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            onBroadcast?(Packet(command:"focusState",text:String(data:data,encoding:.utf8)))
        }
    }
    func testNudge() { notify("A little nudge from Vigil. Ready for your next step?") }
    private func notify(_ text:String,target:CGPoint?=nil) { VigilCharacterHost.shared.nudge(text,target:target);onBroadcast?(Packet(command:"nudge",text:text)) }
    private func encodedState()->String? { (try? JSONEncoder().encode(state)).flatMap{String(data:$0,encoding:.utf8)} }
    private func cancelWork() { generation=UUID();task?.cancel();task=nil }
    private func findMeeting() {
        nextMeeting=nil
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else { return }
        let now=Date(),end=Calendar.current.startOfDay(for:now).addingTimeInterval(86400)
        if let event=events.events(matching:events.predicateForEvents(withStart:now,end:end,calendars:nil))
            .filter({!$0.isAllDay && $0.startDate>now && $0.status != .canceled}).sorted(by:{$0.startDate<$1.startDate}).first {
            nextMeeting=(event.eventIdentifier ?? String(event.startDate.timeIntervalSince1970),event.startDate)
        }
    }
    private func tick() {
        guard state.session?.status == .running else { return }
        let now=ProcessInfo.processInfo.systemUptime,delta=now-lastTick;lastTick=now
        guard delta<15 else { pause();return }
        let console=CGSessionCopyCurrentDictionary() as? [String:Any]
        if console?["CGSSessionScreenIsLocked"] as? Bool == true || console?["kCGSessionOnConsoleKey"] as? Bool == false { pause();return }
        state.session?.advance(max(0,delta))
        if let meeting=nextMeeting,milestones.meetingDue(id:meeting.id,start:meeting.start,now:Date()) {
            end();state.notice="Your next meeting is in \(max(1,Int(ceil(meeting.start.timeIntervalSinceNow/60)))) minutes. A good place to stop."
            notify(state.notice);sync();return
        }
        if milestones.advance(delta) {
            state.notice="A little stretch and a glass of water? Your task will wait."
            notify(state.notice)
        }
        guard let session=state.session else { return }
        if session.status == .ended {
            state.history.removeAll{$0.id==session.id};state.history.insert(session,at:0);cancelWork();sync();return
        }
        if Int(session.elapsed)%60==0 { flushParkingLot();findMeeting() }
        // Send small heartbeat snapshots; the timer remains Mac-authoritative.
        if Int(session.elapsed)%5==0 { sync() }
        guard task==nil,session.elapsed-lastCheck>=settings.safeInterval else { return }
        lastCheck=session.elapsed;let token=generation
        task=Task { [weak self] in
            guard let self else { return }
            defer { if generation==token { task=nil } }
            do {
                try WorkScreenGuard.check()
                guard let key=KeyVault.read() else { throw RouterError.keyMissing }
                let snapshot=try await VigilScreen.capture()
                guard generation==token,!Task.isCancelled else { return }
                let captured=ProcessInfo.processInfo.systemUptime
                let answer=try await router.classify(jpeg:snapshot.jpeg,ocr:snapshot.ocr,app:snapshot.app,task:session.task,key:key,
                    allowPaid:settings.allowPaidFallback,permitsSend:{ @Sendable [weak self] in
                        await MainActor.run {
                            guard let self,self.generation==token,self.state.session?.status == .running,
                                  ProcessInfo.processInfo.systemUptime-captured<20 else { return false }
                            return (try? WorkScreenGuard.check()) != nil
                        }
                    })
                guard generation==token,!Task.isCancelled else { return }
                let age=ProcessInfo.processInfo.systemUptime-captured
                var check=FocusCheck(elapsed:state.session?.elapsed ?? session.elapsed,activity:age<=20 ? answer.activity : .unavailable,
                    probability:answer.probability,confidence:answer.confidence,probabilities:answer.probabilities,sampleDuration:settings.safeInterval)
                if policy.observe(check,age:age) {
                    let message=await router.nudge(task:session.task,key:key,allowPaid:settings.allowPaidFallback,
                        goKey:KeyVault.read(service:"com.kafworlddigital.vigil.opencode"),permitsSend:{ @Sendable [weak self] in
                            await MainActor.run { guard let self,self.generation==token else { return false }; return (try? WorkScreenGuard.check()) != nil }
                        })
                    guard generation==token,!Task.isCancelled else { return }
                    try WorkScreenGuard.check()
                    check.nudged=true;state.notice=message;notify(message,target:VigilPointing.currentWindow())
                }
                state.session?.checks.append(check);state.session?.detail=check.activity == .uncertain ? "Not enough context to judge" : check.activity == .onTask ? "On task" : "Checking gently before nudging"
                let usage=await router.currentUsage();state.model=usage.lastModel;state.costUSD=usage.cost;state.requestsToday=usage.requests
                sync()
            } catch {
                guard generation==token,!Task.isCancelled else { return }
                policy.reset()
                let privateSkip=(error as? RouterError) == .privateScreen
                state.session?.checks.append(FocusCheck(elapsed:session.elapsed,activity:privateSkip ? .privateSkipped : .unavailable,sampleDuration:settings.safeInterval))
                state.session?.detail=privateSkip ? "private (skipped)" : (error as? RouterError)?.localizedDescription ?? "Check unavailable. Your timer is still running."
                let usage=await router.currentUsage();state.model=usage.lastModel;state.costUSD=usage.cost;state.requestsToday=usage.requests
                if (error as? RouterError) == .dailyLimit { lastCheck=(state.session?.elapsed ?? 0)+3600 }
                sync()
            }
        }
    }
}
@MainActor private final class VigilNudgePanel {
    private var panel:NSPanel?
    private var label:NSTextField?
    private var hide:DispatchWorkItem?
    func show(_ text:String) {
        guard let screen=NSScreen.main else { return }
        if panel==nil {
            let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:360,height:104),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.level = .floating
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true
            let material=NSVisualEffectView(frame:NSRect(x:0,y:0,width:360,height:104));material.material = .popover;material.blendingMode = .behindWindow;material.state = .active
            material.wantsLayer=true;material.layer?.cornerRadius=18;material.layer?.masksToBounds=true
            let label=NSTextField(wrappingLabelWithString:"");label.font = .systemFont(ofSize:15,weight:.medium);label.frame=NSRect(x:22,y:22,width:316,height:60)
            material.addSubview(label);panel.contentView=material;panel.ignoresMouseEvents=true
            self.label=label;self.panel=panel
        }
        label?.stringValue="Vigil · "+text
        panel?.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-382,y:screen.visibleFrame.minY+28))
        panel?.orderFrontRegardless();hide?.cancel()
        let work=DispatchWorkItem{[weak self] in self?.panel?.orderOut(nil)};hide=work
        DispatchQueue.main.asyncAfter(deadline:.now()+10,execute:work)
    }
}
#endif
