import SwiftUI
#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins
#endif

@main struct VigilApp:App {
    #if os(macOS)
    @StateObject private var engine=MacFocusEngine()
    @StateObject private var server=MacDeviceServer()
    var body:some Scene {
        WindowGroup("Vigil") { MacRoot(engine:engine,server:server).frame(minWidth:640,minHeight:640) }
            .defaultSize(width:760,height:800)
        MenuBarExtra("Vigil",systemImage:"eye"){
            Text(engine.state.session?.task ?? "Ready when you are.")
            Text(engine.state.session?.detail ?? engine.state.notice)
            Divider()
            Button("Pause focus"){engine.pause()}.disabled(engine.state.session?.status != .running)
            Button("Resume focus"){engine.resume()}.disabled(engine.state.session?.status != .paused)
            Button("End session"){engine.end()}
            SettingsLink()
            Divider();Button("Quit Vigil"){NSApplication.shared.terminate(nil)}
        }
        Settings { VigilSettingsView(state:engine.state,changed:engine.updateSettings).frame(width:460).padding() }
    }
    #else
    var body:some Scene { WindowGroup{PhoneRoot()} }
    #endif
}

private struct VigilCharacter:View {
    var listening:Bool=false
    var body:some View {
        ZStack {
            Ellipse().fill(.indigo.opacity(0.08)).frame(width:146,height:16).offset(y:67)
            RoundedRectangle(cornerRadius:56,style:.continuous)
                .fill(LinearGradient(colors:[Color(red:0.67,green:0.73,blue:0.97),Color(red:0.31,green:0.37,blue:0.73)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .frame(width:138,height:132).rotationEffect(.degrees(-3))
            HStack(spacing:12){
                ForEach(0..<2){_ in ZStack{Ellipse().fill(.white).frame(width:34,height:42);Ellipse().fill(Color(red:0.12,green:0.15,blue:0.28)).frame(width:13,height:21).offset(x:2,y:2);Circle().fill(.white).frame(width:5).offset(x:4,y:-3)}}
            }.offset(y:-2)
            Capsule().fill(Color.indigo.opacity(0.55)).frame(width:listening ? 20:14,height:listening ? 10:4).offset(y:32)
            Image(systemName:"leaf.fill").font(.system(size:28)).foregroundStyle(Color(red:0.36,green:0.48,blue:0.43)).rotationEffect(.degrees(-25)).offset(x:5,y:-72)
        }.frame(height:174).accessibilityLabel("Vigil, your blueberry focus companion")
    }
}
private struct HoldToTalk:View {
    @ObservedObject var speech:OnDeviceSpeech
    @State private var pressing=false
    var body:some View {
        VStack(spacing:7){
            VigilCharacter(listening:speech.listening)
            Label(speech.listening ? "Listening on this device…":"Hold to talk",systemImage:speech.listening ? "waveform":"mic")
                .font(.subheadline.weight(.medium))
        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{_ in
            if !pressing{pressing=true;Task{await speech.begin()}}
        }.onEnded{_ in pressing=false;speech.finish()})
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Hold while saying your task, or park this followed by an idea")
        .onDisappear{speech.cancel()}
    }
}
struct FocusDashboard:View {
    var state:VigilState
    var connected:Bool
    var connectionText:String
    var command:(String,String?)->Void
    var pairing:()->Void
    @StateObject private var speech=OnDeviceSpeech()
    @StateObject private var calendar=CalendarReader()
    @State private var task=""
    @State private var minutes=30.0
    @State private var idea=""
    @State private var showParking=false
    @State private var showSettings=false
    private var sessions:[FocusSession] {
        guard let s=state.session,!state.history.contains(where:{$0.id==s.id}) else{return state.history}
        return state.history+[s]
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24){
                HStack{VStack(alignment:.leading,spacing:5){Text("Vigil").font(.largeTitle.weight(.semibold));Text("A little company for the task ahead.").font(.subheadline).foregroundStyle(.secondary)};Spacer();Button(action:{showSettings=true}){Image(systemName:"gearshape")}.buttonStyle(.plain).accessibilityLabel("Settings")}
                HStack(spacing:7){Circle().fill(connected ? Color.green:Color.orange).frame(width:7,height:7);Text(connectionText).font(.caption).foregroundStyle(.secondary);Spacer();Button("Pair",action:pairing).font(.caption)}
                HoldToTalk(speech:speech).frame(maxWidth:.infinity)
                if !speech.message.isEmpty{Text(speech.message).font(.callout).foregroundStyle(.secondary)}
                if speech.listening{Text(speech.transcript).font(.callout).frame(maxWidth:.infinity)}
                if let session=state.session,session.status != .ended {
                    VStack(alignment:.leading,spacing:14){
                        Text("YOUR FOCUS").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text(session.task).font(.title2.weight(.medium))
                        Text(FocusSession.clock(session.remaining)).font(.system(size:48,weight:.light,design:.rounded)).monospacedDigit()
                        Text(session.detail).font(.callout).foregroundStyle(.secondary)
                        HStack{Button(session.status == .paused ? "Resume":"Pause"){command(session.status == .paused ? "focusResume":"focusPause",nil)}.buttonStyle(.borderedProminent);Button("Finish"){command("focusEnd",nil)}.buttonStyle(.bordered)}.disabled(!connected)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:20))
                } else {
                    VStack(alignment:.leading,spacing:14){
                        Text("ONE THING AT A TIME").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        TextField("What would you like to focus on?",text:$task,axis:.vertical).font(.title3).textFieldStyle(.plain).lineLimit(2...4)
                        HStack{Picker("Focus for",selection:$minutes){ForEach([10.0,25,30,50,60,90],id:\.self){Text("\(Int($0)) minutes").tag($0)}};Spacer();Button("Start focus"){start(task)}.buttonStyle(.borderedProminent).disabled(task.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !connected)}
                        Button("Use today's calendar"){Task{await calendar.request()}}.font(.callout)
                        if !calendar.message.isEmpty{Text(calendar.message).font(.caption).foregroundStyle(.secondary)}
                        ForEach(calendar.events.prefix(6),id:\.eventIdentifier){event in Button{task=event.title ?? "Meeting preparation"}label:{HStack{Text(event.startDate,style:.time).foregroundStyle(.secondary);Text(event.title ?? "Calendar event").lineLimit(1);Spacer();Image(systemName:"arrow.up.left")}}.buttonStyle(.plain).font(.callout)}
                    }.padding(22).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:20))
                }
                Text(state.notice).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack{TextField("An idea for later…",text:$idea).textFieldStyle(.roundedBorder);Button("Park"){command("focusPark",idea);idea=""}.buttonStyle(.bordered).disabled(idea.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
                HStack{Text("Today").font(.headline);Spacer();Button("Parking lot (\(state.ideas.count))"){showParking=true}.font(.callout)}
                let summary=DailySummary(sessions:sessions,ideas:state.ideas)
                HStack(spacing:0){metric("\(summary.focusMinutes)","focus minutes");Divider();metric("\(summary.driftCount)","gentle nudges");Divider();metric("\(summary.parkedCount)","ideas parked")}.frame(height:70)
                Text("Work screens stay private. Ideas can wait for Sunday.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity)
            }.padding(24).frame(maxWidth:700).frame(maxWidth:.infinity)
        }.tint(Color(red:0.37,green:0.42,blue:0.71))
        .onAppear{speech.onResult=voice;calendar.refresh()}
        .sheet(isPresented:$showParking){ParkingView(ideas:state.ideas)}
        .sheet(isPresented:$showSettings){VigilSettingsView(state:state){value in
            if let data=try? JSONEncoder().encode(value){command("focusSettings",String(data:data,encoding:.utf8))}
        }}
    }
    private func metric(_ value:String,_ label:String)->some View{VStack(spacing:5){Text(value).font(.title2.weight(.medium)).monospacedDigit();Text(label).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity)}
    private func start(_ value:String){
        guard let data=try? JSONSerialization.data(withJSONObject:["task":value,"minutes":minutes]) else{return}
        command("focusStart",String(data:data,encoding:.utf8))
    }
    private func voice(_ value:String){
        let lower=value.lowercased()
        if lower.hasPrefix("park this") {
            let idea=String(value.dropFirst(9)).trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if !idea.isEmpty{command("focusPark",idea)}
        } else {
            var clean=value
            for prefix in ["focus on ","start focus ","start a focus session "] where lower.hasPrefix(prefix){clean=String(value.dropFirst(prefix.count));break}
            task=clean
            if state.session?.status != .running{start(clean)}
        }
    }
}
struct ParkingView:View {
    var ideas:[ParkedIdea]
    @Environment(\.dismiss) private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:16){HStack{Text("Parking lot").font(.title2.weight(.semibold));Spacer();Button("Done"){dismiss()}};Text("Drifter-in-chief · Sunday review").font(.subheadline).foregroundStyle(.secondary);List(ideas.reversed()){idea in VStack(alignment:.leading,spacing:5){Text(idea.text);Text(idea.createdAt,format:.dateTime.weekday().hour().minute()).font(.caption).foregroundStyle(.secondary)}}}.padding(24).frame(minWidth:300,minHeight:400)}
}
struct VigilSettingsView:View {
    var state:VigilState
    var changed:(VigilSettings)->Void
    @State private var value=VigilSettings()
    @State private var key=""
    @State private var goKey=""
    @State private var feedback=""
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            HStack{Text("Settings").font(.title2.weight(.semibold));Spacer();Button("Done"){dismiss()}}
            Text("Vigil \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:8){Text("Screen checks").font(.headline);Text("Every \(Int(value.safeInterval)) seconds");Slider(value:$value.interval,in:30...120,step:30).onChange(of:value.interval){_,_ in changed(value)};Text("Checks run only during a declared task. Free requests have a daily limit; the timer keeps running if they run out.").font(.caption).foregroundStyle(.secondary)}
            Toggle("Allow paid fallback",isOn:$value.allowPaidFallback).onChange(of:value.allowPaidFallback){_,_ in changed(value)}
            Text(value.allowPaidFallback ? "Cheap fallback only, up to $0.20 input / $0.80 output per million tokens. A configured OpenCode Go key can be used for wording.":"Free models only.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Model in use",value:state.model)
            LabeledContent("Running cost",value:String(format:"$%.2f",state.costUSD))
            LabeledContent("Requests today",value:"\(state.requestsToday) / 50 safe allowance")
            Divider();Text("OpenRouter key").font(.headline)
            SecureField("Paste a key",text:$key).textFieldStyle(.roundedBorder)
            Button("Save securely"){
                do{try KeyVault.write(key);key="";feedback="Saved in this device's Keychain."}catch{feedback="Couldn't save the key. Please try again."}
            }.disabled(key.isEmpty)
            #if os(macOS)
            Button("Read Orca API Key from Tuck"){feedback=KeyVault.importTuckIfAvailable() ? "OpenRouter key is ready.":"Tuck keeps this key private. Copy it from Tuck and paste it above."}
            DisclosureGroup("Optional OpenCode Go wording"){
                SecureField("Paste an existing Go key",text:$goKey).textFieldStyle(.roundedBorder)
                Button("Save Go key securely"){
                    do{try KeyVault.write(goKey,service:"com.kafworlddigital.vigil.opencode");goKey="";feedback="Go key saved. Used only with paid fallback enabled."}catch{feedback="Couldn't save that key."}
                }.disabled(goKey.isEmpty)
                Text("Uses your existing Go allowance for short reminders. Go usage is separate from the OpenRouter cost above.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Allow screen checks"){_ = CGRequestScreenCaptureAccess()}
            Text("Only non-work screens go to OpenRouter. Calendar is read only; speech stays on this Mac.").font(.caption).foregroundStyle(.secondary)
            #else
            Text("Your Mac needs its own OpenRouter key. Keys are never sent over pairing.").font(.caption).foregroundStyle(.secondary)
            #endif
            if !feedback.isEmpty{Text(feedback).font(.callout)}
            Divider();Text("Work privacy guard").font(.headline)
            ForEach(PrivacyGuard.displayList,id:\.self){Text($0).font(.callout)}
            Text("Any visible work window skips the whole check. It is recorded as private (skipped), never off-task.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:600,alignment:.leading)}.frame(minWidth:300,minHeight:500).onAppear{value=state.settings;feedback=KeyVault.read() != nil ? "OpenRouter key is ready.":"Paste your OpenRouter key to enable checks."}
    }
}
#if os(macOS)
struct MacRoot:View {
    @ObservedObject var engine:MacFocusEngine
    @ObservedObject var server:MacDeviceServer
    @State private var showPair=false
    var body:some View {
        FocusDashboard(state:engine.state,connected:true,connectionText:server.phones.isEmpty ? "Mac ready · no companion paired yet":"Connected · \(server.phones.joined(separator:", "))",command:{name,text in
            if name=="focusStart",!CGPreflightScreenCaptureAccess(){_ = CGRequestScreenCaptureAccess()}
            engine.receive(Packet(command:name,text:text)){_ in}
        },pairing:{showPair=true})
        .safeAreaInset(edge:.bottom){if !engine.error.isEmpty{Text(engine.error).font(.callout).padding()}}
        .task{engine.onBroadcast=server.broadcast;server.onPacket=engine.receive;server.start();engine.sync()}
        .sheet(isPresented:$showPair){MacPairView(record:server.pairing)}
    }
}
struct MacPairView:View {
    var record:PairingRecord?
    @Environment(\.dismiss) private var dismiss
    var body:some View{VStack(spacing:18){HStack{Text("Pair your companion").font(.title2);Spacer();Button("Done"){dismiss()}};Text("Open Vigil on your iPhone or iPad, tap Pair, then scan. Keep both devices on the same Wi-Fi.").foregroundStyle(.secondary)
        if let record,let image=qr(record.qrText){Image(nsImage:image).interpolation(.none).resizable().frame(width:250,height:250);Button("Copy pairing code"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(record.qrText,forType:.string)}}
    }.padding(30).frame(width:430)}
    private func qr(_ text:String)->NSImage?{let filter=CIFilter.qrCodeGenerator();filter.message=Data(text.utf8);guard let output=filter.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)),let image=CIContext().createCGImage(output,from:output.extent) else{return nil};return NSImage(cgImage:image,size:NSSize(width:250,height:250))}
}
#else
struct PhoneRoot:View {
    @StateObject private var link=PhoneDeviceLink()
    @State private var showPair=false
    @Environment(\.scenePhase) private var phase
    var body:some View{
        FocusDashboard(state:link.state,connected:link.connected && link.fresh,connectionText:link.connected ? (link.fresh ? "Your Mac is connected":"Reconnecting to your Mac…"):link.message,command:link.send,pairing:{showPair=true})
            .task{link.start()}
            .onChange(of:link.state.session?.status){_,status in UIApplication.shared.isIdleTimerDisabled = status == .running && phase == .active}
            .onChange(of:phase){_,new in
                if new == .active{link.start();link.send("focusSync");UIApplication.shared.isIdleTimerDisabled = link.state.session?.status == .running}
                else{link.stop();UIApplication.shared.isIdleTimerDisabled=false}
            }
            .sheet(isPresented:$showPair){PhonePairView(link:link)}
    }
}
struct PhonePairView:View {
    @ObservedObject var link:PhoneDeviceLink
    @State private var code=""
    @State private var scan=false
    @Environment(\.dismiss) private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:20){HStack{Text("Pair your Mac").font(.title2);Spacer();Button("Done"){dismiss()}};Text("On your Mac, open Vigil and choose Pair. Scan its code here, on the same Wi-Fi.").foregroundStyle(.secondary)
        if scan{VigilQRScanner{if link.pair($0){dismiss()}}.frame(height:300).clipShape(RoundedRectangle(cornerRadius:16))}else{Button("Scan Mac code"){scan=true}.buttonStyle(.borderedProminent)}
        SecureField("Or paste the pairing code",text:$code).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("Pair with code"){if link.pair(code){code="";dismiss()}}.disabled(code.isEmpty)
        Text(link.message).font(.caption).foregroundStyle(.secondary);Spacer()
    }.padding(24)}
}
#endif
