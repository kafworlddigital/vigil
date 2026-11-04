import SwiftUI

struct VigilIntroView:View {
    var done:()->Void
    @State private var page=0
    private let cards:[(String,String,String)]=[
        ("eye","A little company for your task","Choose one thing to focus on. Vigil keeps time, offers a gentle nudge and saves ideas for later."),
        ("face.smiling","Your face on Mac and phone","Vigil sits quietly on your Mac and comes alive on your phone. Hold Option and drag the Mac face to move it."),
        ("iphone.landscape","Pair, then prop it sideways","Open Pair on your Mac, then scan its code on your iPhone on the same Wi-Fi. Prop the phone sideways under your screen."),
        ("mic","Hold to talk","Hold the face while you say your task. Let go when you're finished. Speech stays on this device."),
        ("tray","Give ideas a parking space","Say ‘park this’ followed by an idea, or type it in the parking lot. Your ideas will be waiting when you're ready."),
        ("hand.raised","Your screen stays yours","Eligible checks send your task, screen text and image to a model. Vigil saves no screenshots. Protected work windows skip checks; speech stays on-device.")
    ]
    var body:some View {
        GeometryReader{geometry in
            ScrollView{
                VStack(spacing:18){
                    HStack{Text("Vigil").font(.headline);Spacer();Button("Skip",action:done).accessibilityIdentifier("intro.skip")}
                    Image(systemName:cards[page].0).font(.system(size:48,weight:.light)).foregroundStyle(Color(red:0.43,green:0.49,blue:0.92)).padding(.top,4)
                    Text(cards[page].1).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text(cards[page].2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:7){ForEach(cards.indices,id:\.self){index in Circle().fill(index==page ? Color.accentColor:Color.secondary.opacity(0.25)).frame(width:6,height:6)}}
                    HStack{
                        if page>0{Button("Back"){page-=1}};Spacer()
                        Button(page==cards.count-1 ? "Let's begin":"Next"){
                            if page==cards.count-1{done()}else{page+=1}
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("intro.next")
                    }
                }.padding(24).frame(maxWidth:540).frame(maxWidth:.infinity,minHeight:geometry.size.height)
            }
        }.frame(minWidth:300,minHeight:260).background(.background)
    }
}
struct VigilIntroModifier:ViewModifier {
    @AppStorage("vigil.intro.completed") private var completed=false
    @State private var showing=false
    func body(content:Content)->some View {
        content
            .sheet(isPresented:$showing){VigilIntroView{completed=true;showing=false}.frame(idealWidth:520,idealHeight:440).interactiveDismissDisabled()}
            .onAppear{showing = !completed && !ProcessInfo.processInfo.arguments.contains("--vigil-skip-intro")}
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("vigil.showIntro"))){_ in showing=true}
    }
}
extension View {func vigilIntro()->some View {modifier(VigilIntroModifier())}}

/// CI takes screenshots of the same views used in the product, on a fresh simulator.
struct VigilProofScreen<Content:View>:View {
    var state:VigilState
    @ViewBuilder var content:()->Content
    private var screen:String? {let args=ProcessInfo.processInfo.arguments;guard let i=args.firstIndex(of:"--vigil-screen"),i+1<args.count else{return nil};return args[i+1]}
    var body:some View {
        Group {
            if screen=="intro" {VigilIntroView{}}
            else if screen=="help" {VigilHelpView()}
            else if screen=="settings" {VigilSettingsView(state:state,changed:{_ in})}
            else {content().vigilIntro()}
        }.task{VigilAI.shared.start()}
    }
}
