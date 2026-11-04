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
    @AppStorage(CompanionPreferences.cornerKey) private var corner="bottomRight"
    @Environment(\.scenePhase) private var phase
    var body:some View {
        ZStack {
            GeometryReader { geometry in
                let selected=CompanionCorner(rawValue:corner) ?? .bottomRight
                let width=min(520,max(220,geometry.size.width*0.52))
                FaceView(animator:link.face,transparent:true)
                    .frame(width:width,height:width*390/844)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:selected.alignment)
                    .padding(.top,64).padding(.bottom,80)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).updating($held){_,value,_ in value=true}
                        .onChanged{value in
                            let cx=selected.left ? width/2:geometry.size.width-width/2
                            let cy=selected.top ? 64+width*390/844/2:geometry.size.height-80-width*390/844/2
                            link.face.touchGaze=CGPoint(x:(value.location.x-cx)/max(width/2,1),y:(value.location.y-cy)/max(width/3,1))
                        }.onEnded{_ in link.face.touchGaze=nil})
            }
            VStack(alignment:.leading,spacing:6){
                HStack(alignment:.top){
                    VStack(alignment:.leading,spacing:3){
                        Text(active?.task ?? "What's the mission?").font(.fredoka(22)).lineLimit(2)
                        Text(link.connected ? (link.fresh ? active?.detail ?? "Hold Vigil and describe a task" : "Waiting for your Mac…") : "Pair your Mac · keep both on the same Wi-Fi").font(.plexMono(10))
                    }.frame(maxWidth:380,alignment:.leading)
                    Spacer()
                    Menu{ForEach([Mood.happy,.surprised,.listening,.sleepy,.thinking],id:\.rawValue){mood in Button(mood.title){link.face.localMood=mood;link.send("faceMood",text:mood.rawValue)}};Button("Automatic expressions"){link.face.localMood=nil;link.send("faceRelease")}}label:{Image(systemName:"face.smiling")}.accessibilityLabel("Expressions")
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
                    TimelineView(.periodic(from:.now,by:1)){timeline in
                        let remaining=active.map{max(0,$0.remaining-($0.status == .running && link.fresh ? max(0,min(6,timeline.date.timeIntervalSince(link.state.sentAt))):0))} ?? 1800
                        Text(FocusSession.clock(remaining)).font(.system(size:70,weight:.semibold,design:.rounded)).monospacedDigit().minimumScaleFactor(0.6)
                    }
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
    var body:some View {FocusTimeline(session:session)}
}
struct VigilHistoryView:View {
    var sessions:[FocusSession]
    @Environment(\.dismiss) private var dismiss
    var body:some View {VStack(alignment:.leading){HStack{Text("Focus history").font(.title2);Spacer();Button("Done"){dismiss()}}
        List(sessions.reversed()){session in FocusSummary(session:session)}
    }.padding(24).frame(minWidth:300,minHeight:300)}
}
