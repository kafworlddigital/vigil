import SwiftUI

extension CompanionCorner {
    var alignment:Alignment {
        switch self {case .topLeft:return .topLeading;case .topRight:return .topTrailing;case .bottomLeft:return .bottomLeading;case .bottomRight:return .bottomTrailing}
    }
}

struct VigilIntroView:View {
    var done:()->Void
    @State private var page:Int
    @AppStorage(CompanionPreferences.nameKey) private var name="Vigil"
    @AppStorage(CompanionPreferences.colourKey) private var colour="blueberry"
    init(initialPage:Int=0,done:@escaping ()->Void){self.done=done;_page=State(initialValue:min(5,max(0,initialPage)))}
    private var friend:String {let v=name.trimmingCharacters(in:.whitespacesAndNewlines);return v.isEmpty ? "Vigil":String(v.prefix(24))}
    private var title:String {
        switch page {
        case 0:return "Meet \(friend)."
        case 1:return "One task. Your timer."
        case 2:return VigilEdition.friend ? "It sleeps while you focus." : "A nudge when you drift."
        case 3:return "Park it. Come back later."
        case 4:return "Ask \(friend) anything."
        default:return "Make \(friend) yours."
        }
    }
    private var detail:String {
        switch page {
        case 0:return VigilEdition.friend ? "A small face in the corner of your screen that helps you stay on one task." : "A small friend in the corner of your screen. Here to help you stay on one task."
        case 1:return "Pick one thing to do. Choose how long. Start."
        case 2:return VigilEdition.friend ? "While you stay focused, the face dozes off. Drift away and it wakes up, pays attention and points you back to your task." : "Your cursor buddy points you back to your task."
        case 3:return "Save stray ideas in the Parking Lot. Your task can keep its place."
        case 4:return "Free AI help. No setup. Just type a question."
        default:return "Change anything below. It saves as you go."
        }
    }
    var body:some View {
        GeometryReader{geometry in
            let wide=geometry.size.width>600 && geometry.size.height<560
            VStack(spacing:0){
                HStack{
                    Text(wide && page==5 ? "Make \(friend) yours.":"VIGIL").font(wide && page==5 ? .title2.weight(.semibold):.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(page+1) of 6").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Skip",action:done).font(.body.weight(.medium)).padding(.leading,14).accessibilityIdentifier("intro.skip")
                }.padding(.horizontal,24).padding(.vertical,16)
                ScrollView{
                    Group{
                        if wide && page==5 {
                            HStack(alignment:.center,spacing:24){
                                IntroFeaturePicture(page:page).frame(width:geometry.size.width*0.28,height:190)
                                CompanionControls(compact:true)
                            }
                        }else if wide{
                            HStack(alignment:.center,spacing:28){
                                IntroFeaturePicture(page:page).frame(width:geometry.size.width*0.40,height:230)
                                copyAndControls
                            }
                        }else{
                            VStack(alignment:.leading,spacing:22){
                                IntroFeaturePicture(page:page).frame(height:page==5 ? 150:230)
                                copyAndControls
                            }.frame(maxWidth:560)
                        }
                    }.padding(.horizontal,24).padding(.vertical,8).frame(maxWidth:.infinity)
                }.scrollIndicators(.hidden)
                HStack(spacing:12){
                    if page>0{Button("Back"){page-=1}.font(.body)}
                    Spacer()
                    HStack(spacing:6){ForEach(0..<6,id:\.self){index in Capsule().fill(index==page ? Color(hex:Palette.gradient[2]):Color.secondary.opacity(0.22)).frame(width:index==page ? 18:6,height:6)}}.accessibilityLabel("Card \(page+1) of 6")
                    Spacer()
                    Button(page==5 ? "Let's begin":"Next"){
                        if page==5{done()}else{page+=1}
                    }.font(.body.weight(.semibold)).buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("intro.next")
                }.padding(.horizontal,24).padding(.vertical,16)
            }.background(.background).tint(Color(hex:Palette.gradient[3]))
        }.frame(minWidth:300,minHeight:280)
    }
    private var copyAndControls:some View {
        VStack(alignment:.leading,spacing:12){
            Text(title).font(.system(.largeTitle,design:.rounded,weight:.bold)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            Text(detail).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if page==5{CompanionControls().padding(.top,6)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// These cards use the production animated face and the cursor's original path and palette.
struct IntroFeaturePicture:View {
    let page:Int
    @State private var gaze:CGPoint?
    @AppStorage(CompanionPreferences.cornerKey) private var corner="bottomRight"
    @AppStorage(CompanionPreferences.colourKey) private var colour="blueberry"
    @AppStorage(CompanionPreferences.nudgeKey) private var nudge="gentle"
    var body:some View {
        GeometryReader{g in
            let width=g.size.width
            ZStack{
                RoundedRectangle(cornerRadius:24).fill(Color(red:0.065,green:0.075,blue:0.14))
                VStack(alignment:.leading,spacing:0){
                    HStack(spacing:5){ForEach(0..<3,id:\.self){i in Circle().fill([Color(red:0.96,green:0.52,blue:0.52),Color(red:0.95,green:0.75,blue:0.36),Color(red:0.45,green:0.77,blue:0.64)][i]).frame(width:7,height:7)};Spacer();Text(page==3 ? "PARKING LOT":page==4 ? "ASK VIGIL":"YOUR SCREEN").font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.55))}.padding(16)
                    Group{
                        switch page {
                        case 1:
                            VStack(alignment:.leading,spacing:8){
                                Text("Write the first draft").font(.system(size:18,weight:.medium))
                                Text("25:00").font(.system(size:44,weight:.light,design:.rounded)).monospacedDigit()
                                Text("Start focus").font(.system(size:13,weight:.semibold)).padding(.horizontal,16).padding(.vertical,8).background(Color(hex:Palette.gradient[2]),in:Capsule())
                            }.padding(.horizontal,22)
                        case 2:
                            VStack(alignment:.leading,spacing:12){
                                Text("YOUR TASK").font(.system(size:10,weight:.semibold)).foregroundStyle(.white.opacity(0.5))
                                Text("Write the first draft").font(.system(size:18,weight:.medium))
                                Text(CompanionNudge(rawValue:nudge)?.example ?? CompanionNudge.gentle.example).font(.system(size:15,weight:.medium)).foregroundStyle(Color(hex:Palette.nose)).padding(12).background(.white,in:RoundedRectangle(cornerRadius:14))
                            }.padding(.horizontal,22).padding(.trailing,40)
                        case 3:
                            VStack(alignment:.leading,spacing:9){
                                Text("An idea for later…").foregroundStyle(.white.opacity(0.6))
                                HStack{Text("Try a new recipe");Spacer();Text("Park").fontWeight(.semibold).foregroundStyle(Color(hex:Palette.gradient[0]))}.padding(12).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:12))
                                Text("Saved for later").font(.system(size:12)).foregroundStyle(.white.opacity(0.6))
                            }.font(.system(size:15)).padding(.horizontal,22)
                        case 4:
                            VStack(alignment:.leading,spacing:10){
                                Text("How do I get started?").font(.system(size:15,weight:.medium)).padding(12).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:14)).frame(maxWidth:.infinity,alignment:.trailing)
                                Text("Start with a rough first sentence.").font(.system(size:15)).padding(12).background(Color(hex:Palette.gradient[3]),in:RoundedRectangle(cornerRadius:14)).padding(.trailing,35)
                            }.padding(.horizontal,22)
                        default:
                            VStack(alignment:.leading,spacing:10){
                                RoundedRectangle(cornerRadius:4).fill(.white.opacity(0.12)).frame(width:width*0.43,height:10)
                                RoundedRectangle(cornerRadius:4).fill(.white.opacity(0.065)).frame(width:width*0.60,height:7)
                                RoundedRectangle(cornerRadius:4).fill(.white.opacity(0.065)).frame(width:width*0.35,height:7)
                            }.padding(.horizontal,22)
                        }
                    }.foregroundStyle(.white)
                    Spacer(minLength:0)
                }
                IntroLivingFace(mood:page==2 ? .pointing:(VigilEdition.friend && page==1 ? .sleepy:.listening),gaze:gaze)
                    .frame(width:page==0 || page==5 ? min(220,width*0.56):120,height:page==0 || page==5 ? min(220,width*0.56)*390/844:56)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:page==0 || page==5 ? (CompanionCorner(rawValue:corner) ?? .bottomRight).alignment:.bottomTrailing)
                    .padding(.top,34).padding(.horizontal,14).padding(.bottom,page==5 ? 8:14)
                if page==2{
                    IntroCursorBuddy().frame(width:60,height:60).rotationEffect(.degrees(-12)).position(x:width*0.78,y:g.size.height*0.58)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover{phase in
                switch phase {case .active(let p):gaze=CGPoint(x:(p.x-width/2)/max(1,width/2),y:(p.y-g.size.height/2)/max(1,g.size.height/2));case .ended:gaze=nil}
            }
            .simultaneousGesture(DragGesture(minimumDistance:0).onChanged{value in gaze=CGPoint(x:(value.location.x-width/2)/max(1,width/2),y:(value.location.y-g.size.height/2)/max(1,g.size.height/2))}.onEnded{_ in gaze=nil})
            .clipShape(RoundedRectangle(cornerRadius:24)).overlay{RoundedRectangle(cornerRadius:24).strokeBorder(.white.opacity(0.10),lineWidth:1)}
        }.accessibilityLabel(page==2 ? "Vigil's cursor buddy pointing back to the task":"Vigil's animated face in the corner of a screen")
    }
}

struct IntroLivingFace:View {
    var mood:Mood = .listening
    var gaze:CGPoint? = nil
    @State private var animator=FaceAnimator()
    var body:some View {
        GeometryReader{g in
            FaceView(animator:animator,transparent:true)
                .contentShape(Rectangle())
                .onContinuousHover{phase in
                    switch phase {case .active(let point):look(point,g.size);case .ended:animator.touchGaze=nil}
                }
                .gesture(DragGesture(minimumDistance:0).onChanged{look($0.location,g.size)}.onEnded{_ in animator.touchGaze=nil})
        }.onAppear{animator.localMood=mood;animator.awake=true}.onChange(of:gaze,initial:true){_,value in animator.touchGaze=value}
    }
    private func look(_ point:CGPoint,_ size:CGSize){animator.touchGaze=CGPoint(x:(point.x-size.width/2)/max(1,size.width/2),y:(point.y-size.height/2)/max(1,size.height/2))}
}

struct IntroCursorBuddy:View {
    var body:some View {
        TimelineView(.animation){timeline in
            Canvas{ctx,size in
                let s=min(size.width,size.height),k=s/96
                let path=Path(Teardrop.path(size:s,tipRadius:6*k))
                ctx.fill(path,with:BlobShape.fill(in:CGRect(origin:.zero,size:CGSize(width:s,height:s))))
                ctx.stroke(path,with:.color(.white),lineWidth:2)
                let blink=timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:3.7)>3.55
                for i in 0..<2{
                    let eye=CGRect(x:(34+CGFloat(i)*24)*k,y:40*k,width:18*k,height:(blink ? 3:18)*k)
                    ctx.fill(Path(ellipseIn:eye),with:.color(.white))
                    if !blink{ctx.fill(Path(ellipseIn:CGRect(x:eye.minX+2*k,y:eye.minY+2*k,width:9*k,height:9*k)),with:.color(Color(hex:Palette.ink)))}
                }
            }
        }
    }
}

struct CompanionControls:View {
    var compact=false
    @AppStorage(CompanionPreferences.nameKey) private var name="Vigil"
    @AppStorage(CompanionPreferences.colourKey) private var colour="blueberry"
    @AppStorage(CompanionPreferences.nudgeKey) private var nudge="gentle"
    @AppStorage(CompanionPreferences.cornerKey) private var corner="bottomRight"
    var body:some View {
        Group {
        if compact {
            Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:9){
                GridRow{Text("Name").fontWeight(.semibold);TextField("Vigil",text:$name).textFieldStyle(.roundedBorder).frame(minHeight:34).accessibilityIdentifier("companion.name")}
                GridRow{Text("Colour").fontWeight(.semibold);HStack(spacing:6){ForEach(CompanionColour.allCases,id:\.self){item in
                    Button{colour=item.rawValue}label:{Circle().fill(LinearGradient(colors:item.colours.map{Color(hex:$0)},startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:28,height:28).padding(4).overlay{Circle().strokeBorder(colour==item.rawValue ? Color.primary:Color.clear,lineWidth:2)}}.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(colour==item.rawValue ? .isSelected:[])
                }}}
                GridRow{Text("Nudges").fontWeight(.semibold);Picker("Nudge style",selection:$nudge){ForEach(CompanionNudge.allCases,id:\.self){Text($0.title).tag($0.rawValue)}}.pickerStyle(.segmented).labelsHidden()}
                GridRow{Text("Corner").fontWeight(.semibold);HStack(spacing:6){ForEach(CompanionCorner.allCases,id:\.self){item in
                    Button{corner=item.rawValue}label:{VStack(spacing:3){RoundedRectangle(cornerRadius:4).strokeBorder(.secondary.opacity(0.4),lineWidth:1).frame(height:22).overlay(alignment:item.alignment){Circle().fill(corner==item.rawValue ? Color.accentColor:Color.secondary).frame(width:7,height:7).padding(4)};Text(item.title).font(.caption2)}.frame(maxWidth:.infinity).padding(4).background(corner==item.rawValue ? Color.accentColor.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(corner==item.rawValue ? .isSelected:[])
                }}}
            }.font(.callout)
        } else {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Name").font(.headline);TextField("Vigil",text:$name).textFieldStyle(.roundedBorder).accessibilityIdentifier("companion.name")}
            VStack(alignment:.leading,spacing:8){
                HStack{Text("Colour").font(.headline);Spacer();Text((CompanionColour(rawValue:colour) ?? .blueberry).title).foregroundStyle(.secondary)}
                HStack(spacing:6){ForEach(CompanionColour.allCases,id:\.self){item in
                    Button{colour=item.rawValue}label:{
                        Circle().fill(LinearGradient(colors:item.colours.map{Color(hex:$0)},startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:36,height:36).padding(4)
                            .overlay{Circle().strokeBorder(colour==item.rawValue ? Color.primary:Color.clear,lineWidth:2)}
                    }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(colour==item.rawValue ? .isSelected:[]).accessibilityIdentifier("companion.colour.\(item.rawValue)")
                }}
            }
            VStack(alignment:.leading,spacing:7){Text("Nudge style").font(.headline);Picker("Nudge style",selection:$nudge){ForEach(CompanionNudge.allCases,id:\.self){Text($0.title).tag($0.rawValue)}}.pickerStyle(.segmented).labelsHidden();Text((CompanionNudge(rawValue:nudge) ?? .gentle).example).font(.callout).foregroundStyle(.secondary)}
            VStack(alignment:.leading,spacing:7){
                Text("Screen corner").font(.headline)
                HStack(spacing:8){ForEach(CompanionCorner.allCases,id:\.self){item in
                    Button{corner=item.rawValue}label:{
                        VStack(spacing:5){RoundedRectangle(cornerRadius:5).strokeBorder(.secondary.opacity(0.35),lineWidth:1).frame(height:32).overlay(alignment:item.alignment){Circle().fill(corner==item.rawValue ? Color(hex:Palette.gradient[2]):Color.secondary).frame(width:8,height:8).padding(5)};Text(item.title).font(.caption)}.frame(maxWidth:.infinity).padding(5).background(corner==item.rawValue ? Color.accentColor.opacity(0.10):Color.clear,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(corner==item.rawValue ? .isSelected:[]).accessibilityIdentifier("companion.corner.\(item.rawValue)")
                }}
            }
            Text("Saved immediately · change these in Settings any time").font(.caption).foregroundStyle(.secondary)
        }
        }
        }
        .onChange(of:name){_,v in if v.count>24{name=String(v.prefix(24))}}
        .onChange(of:corner){_,_ in
            #if os(macOS)
            VigilCharacterHost.shared.placeInCorner()
            #endif
        }
    }
}

struct VigilIntroModifier:ViewModifier {
    // A new intro version shows once even for people who completed the original cards.
    @AppStorage("vigil.intro.v2.completed") private var completed=false
    @State private var showing=false
    func body(content:Content)->some View {
        content.sheet(isPresented:$showing){
            VigilIntroView{completed=true;UserDefaults.standard.set(true,forKey:"vigil.intro.completed");showing=false}
                .frame(idealWidth:720,idealHeight:700).interactiveDismissDisabled()
        }.onAppear{
            let args=ProcessInfo.processInfo.arguments
            if args.contains("--vigil-reset-intro"){completed=false}
            showing = !completed && !args.contains("--vigil-skip-intro")
        }.onReceive(NotificationCenter.default.publisher(for:Notification.Name("vigil.showIntro"))){_ in showing=true}
    }
}
extension View{func vigilIntro()->some View{modifier(VigilIntroModifier())}}

struct VigilProofScreen<Content:View>:View {
    var state:VigilState
    @ViewBuilder var content:()->Content
    private var screen:String?{let a=ProcessInfo.processInfo.arguments;guard let i=a.firstIndex(of:"--vigil-screen"),i+1<a.count else{return nil};return a[i+1]}
    var body:some View {
        Group{
            if let screen,screen.hasPrefix("intro"){
                let number=Int(screen.replacingOccurrences(of:"intro-",with:"")) ?? 1
                VigilIntroView(initialPage:number-1){}
            }else if screen=="help"{VigilHelpView()}
            else if screen=="settings"{VigilSettingsView(state:state,changed:{_ in})}
            else{content().vigilIntro()}
        }.task{VigilAI.shared.start()}
    }
}

struct VigilAskView:View {
    @Environment(\.dismiss) private var dismiss
    @State private var question=""
    @State private var answer=""
    @State private var waiting=false
    @State private var request:Task<Void,Never>?
    var body:some View {
        VStack(alignment:.leading,spacing:20){
            HStack{Text("Ask \(CompanionPreferences().name)").font(.title2.weight(.semibold));Spacer();Button("Done"){request?.cancel();dismiss()}}
            IntroLivingFace().frame(height:100).background(.black,in:RoundedRectangle(cornerRadius:16))
            Text("Free AI help. No setup.").font(.title3)
            TextField("What would you like a hand with?",text:$question,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
            Button(waiting ? "Thinking…":"Ask"){
                let text=String(question.trimmingCharacters(in:.whitespacesAndNewlines).prefix(3000))
                waiting=true;answer=""
                request=Task{@MainActor in
                    defer{waiting=false}
                    do{
                        let reply=try await VigilAI.shared.answer(ModelPrompt(system:"Help with the user's question in clear, brief \(VigilCopy.english). Be practical and honest about uncertainty. You have no tools and cannot act on their device.",text:text))
                        guard !Task.isCancelled else{return}
                        answer=reply.local ? "AI help is unavailable just now. Your timer and Parking Lot still work. Try again shortly.":reply.text
                    }catch{if !Task.isCancelled{answer="Couldn't reach AI help. Try again shortly."}}
                }
            }.buttonStyle(.borderedProminent).disabled(waiting || question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            if !answer.isEmpty{ScrollView{Text(answer).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
            Spacer(minLength:0)
            Text("Your question is sent to Vigil's AI service. Free usage limits apply.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth:300,minHeight:320).onDisappear{request?.cancel()}
    }
}
