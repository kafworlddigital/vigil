#if os(iOS)
import SwiftUI
import UIKit

struct PhoneFaceScreen:View {
    @ObservedObject var link:PhoneDeviceLink
    var pair:()->Void
    @StateObject private var speech=OnDeviceSpeech()
    @GestureState private var held=false
    @State private var dashboard=false
    @State private var inspect=false
    @Environment(\.scenePhase) private var phase
    var body:some View {
        ZStack {
            FaceView(animator:link.face)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).updating($held){_,value,_ in value=true})
            VStack(alignment:.leading,spacing:6){
                HStack(alignment:.top){
                    VStack(alignment:.leading,spacing:3){
                        Text(active?.task ?? "What's the mission?").font(.fredoka(22)).lineLimit(2)
                        Text(link.connected ? (link.fresh ? active?.detail ?? "Hold Vigil and describe a task" : "Waiting for your Mac…") : "Pair your Mac · keep both on the same Wi-Fi").font(.plexMono(10))
                    }.frame(maxWidth:380,alignment:.leading)
                    Spacer()
                    Button(action:pair){Image(systemName:"qrcode.viewfinder")}.accessibilityLabel("Pair Mac")
                    Button{dashboard=true}label:{Image(systemName:"gearshape")}.accessibilityLabel("Focus, parking lot, calendar and Settings")
                }
                if !link.nudge.isEmpty{Text(link.nudge).font(.fredoka(16)).foregroundStyle(Color(hex:Palette.nose)).padding(12).background(.white,in:RoundedRectangle(cornerRadius:18)).frame(maxWidth:480)}
                if speech.listening{Text(speech.transcript.isEmpty ? "Listening…":speech.transcript).font(.plexSans(14))}
                if !speech.message.isEmpty{Text(speech.message).font(.caption)}
                Spacer()
                if let active { Button{inspect=true}label:{FocusTimelineStrip(session:active).frame(height:12)}.buttonStyle(.plain).accessibilityLabel("Inspect on-task and off-task timeline") }
                HStack(alignment:.bottom,spacing:14){
                    if let active {
                        Button{link.send(active.status == .paused ? "focusResume":"focusPause")}label:{Image(systemName:active.status == .paused ? "play.fill":"pause.fill")}.disabled(!link.fresh)
                        Button{link.send("focusEnd")}label:{Image(systemName:"stop.fill")}.disabled(!link.fresh)
                    }
                    Button{dashboard=true}label:{Image(systemName:"scope")}.accessibilityLabel("Focus sessions")
                    Image(systemName:speech.listening ? "mic.fill":"mic").accessibilityLabel("Hold Vigil to talk")
                    Spacer()
                    Text(FocusSession.clock(active?.remaining ?? 1800)).font(.system(size:70,weight:.semibold,design:.rounded)).monospacedDigit().minimumScaleFactor(0.6)
                }
            }.padding(.horizontal,24).padding(.vertical,16).foregroundStyle(.white).buttonStyle(.plain)
        }.background(.black).persistentSystemOverlays(.hidden)
        .onAppear{speech.onResult=voice}
        .onChange(of:held){_,down in
            if down {link.face.localMood = .listening;link.send("faceMood",text:"listening");Task{@MainActor in if held {await speech.begin()}}}
            else {speech.finish();link.face.localMood = .thinking;link.send("faceMood",text:"thinking");DispatchQueue.main.asyncAfter(deadline:.now()+2){link.face.localMood=nil;link.send("faceRelease")}}
        }
        .onChange(of:phase){_,p in if p != .active{speech.cancel();link.face.localMood=nil}}
        .onDisappear{speech.cancel()}
        .sheet(isPresented:$dashboard){FocusDashboard(state:link.state,connected:link.connected && link.fresh,connectionText:link.message,command:link.send,pairing:pair)}
        .sheet(isPresented:$inspect){VigilHistoryView(sessions:link.state.history+(active.map{[$0]} ?? []))}
    }
    private var active:FocusSession? {link.state.session.flatMap{$0.status == .ended ? nil:$0}}
    private func voice(_ text:String){
        if text.lowercased().hasPrefix("park this") {link.send("focusPark",text:String(text.dropFirst(9)).trimmingCharacters(in:.punctuationCharacters.union(.whitespacesAndNewlines)))}
        else {
            var task=text
            for prefix in ["focus on ","start focus "] where text.lowercased().hasPrefix(prefix){task=String(text.dropFirst(prefix.count));break}
            if let data=try? JSONSerialization.data(withJSONObject:["task":task,"minutes":30]){link.send("focusStart",text:String(data:data,encoding:.utf8))}
        }
    }
}
#endif

import SwiftUI
struct FocusTimelineStrip:View {
    let session:FocusSession
    var body:some View {GeometryReader{geo in
        ZStack(alignment:.leading){Rectangle().fill(.gray.opacity(0.4))
            ForEach(Array(session.checks.enumerated()),id:\.offset){_,check in
                let duration=max(1,session.elapsed)
                Rectangle().fill(check.activity == .onTask ? Color.green:check.activity == .offTask ? Color(hex:0xFFC2A4):Color.gray)
                    .frame(width:max(1,geo.size.width*min(check.sampleDuration ?? 60,duration)/duration))
                    .offset(x:geo.size.width*min(check.elapsed,duration)/duration)
            }
        }.clipped()
    }}
}
struct VigilHistoryView:View {
    var sessions:[FocusSession]
    @Environment(\.dismiss) private var dismiss
    var body:some View {VStack(alignment:.leading){HStack{Text("Focus history").font(.title2);Spacer();Button("Done"){dismiss()}}
        List(sessions.reversed()){session in VStack(alignment:.leading,spacing:8){Text(session.task).font(.headline);FocusTimelineStrip(session:session).frame(height:12)
            ForEach(Array(session.checks.enumerated()),id:\.offset){_,c in HStack{Text(FocusSession.clock(c.elapsed));Text(c.activity.rawValue);Spacer();Text(String(format:"%.0f%% off-task estimate",c.probability*100))}.font(.caption)}
        }}
    }.padding(24).frame(minWidth:300,minHeight:300)}
}
