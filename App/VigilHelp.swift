import SwiftUI

struct VigilHelpView:View {
    @Environment(\.dismiss) private var dismiss
    private let topics:[(String,String)]=[
        ("Focus sessions","Choose one task and a time, then press Start focus. Pause for a break or Finish when you're done. Your history shows the checks and ideas from each session."),
        ("The face","The Mac face follows your pointer. Hold Option and drag to move it; change its size in Settings. On a paired phone, the face keeps you company beside your screen. Prop the phone sideways below the monitor."),
        ("Pairing","On the Mac choose Pair. On your phone tap Pair and point the camera at the QR code. Keep both on the same Wi-Fi. Each edition has its own private pairing."),
        ("Hold to talk","Hold the face, say your task and release. Say ‘park this’ before an idea to save it for later. Speech recognition runs on your device. You can always type instead."),
        ("Nudges","During a focus session, repeated clear signs of drift can bring a kind reminder. Ambiguous or protected screens do not count as drift. Test a nudge from the Mac menu."),
        ("The parking lot","Type an idea and press Park, or say ‘park this’ followed by the idea. Open Parking lot to revisit it. Parking an idea leaves your current task in place."),
        ("Calendar","Choose Use today's calendar and allow access to read your events. Pick an event as your task. Vigil never changes your calendar. The Mac can give a ten-minute meeting reminder."),
        ("Models and status dots","Settings lists each model. Green means its latest check answered; amber means waiting or limited; red means unavailable. Test all now repeats eligible checks. Checks run at launch and every 30 minutes. Vigil tries available models in speed order and moves on after an error or timeout. Limited models rest until their retry time. Only vision models see screen checks. If remote models fail, on-device help keeps the session going."),
        ("Privacy","Your tasks, ideas and history stay on your own devices. Pairing is encrypted. Speech stays on-device. Protected work windows skip the whole screen check. Eligible images are sent transiently for a check and are never saved by Vigil. Model providers apply their own retention policies. The server does not store prompts, images or conversations. Macy's edition has separate data and per-device access; provider keys are never bundled or paired."),
        ("iPhone not pairing","Open Vigil on both devices, keep them on the same Wi-Fi and scan a fresh Mac code. In your device's Settings allow Vigil access to Local Network and Camera. A sleeping Mac or a Wi-Fi network that separates devices can prevent pairing."),
        ("No AI answers","Open Settings and press Test all now. Amber models may be waiting for a usage reset; red models may have a connection or credential problem. Check your internet connection. Your timer, parking lot and local fallback keep working. TestFlight editions connect automatically; no provider key is needed."),
        ("Permissions","For reminders, allow Notifications. For voice, allow Microphone and Speech Recognition. For pairing, allow Local Network and Camera on the phone. For calendar, allow Calendar access. On the Mac allow Screen Recording only if you want screen checks. If you declined, change the permission in the device's Settings, then reopen Vigil.")
    ]
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20){
            HStack{Text("Vigil Help").font(.largeTitle.weight(.semibold));Spacer();Button("Done"){dismiss()}}
            Text("A little company for the task ahead.").foregroundStyle(.secondary)
            ForEach(topics.indices,id:\.self){i in VStack(alignment:.leading,spacing:7){Text(topics[i].0).font(.headline);Text(topics[i].1).fixedSize(horizontal:false,vertical:true).foregroundStyle(.secondary)}}
            Link("Report a problem",destination:VigilSupport.reportURL)
        }.padding(24).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity,alignment:.center)}.frame(minWidth:300,minHeight:300)
    }
}
enum VigilSupport {
    static var version:String {"Vigil \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "4"))"}
    static var reportURL:URL {
        var parts=URLComponents();parts.scheme="mailto";parts.path="contact@kafworlddigital.com"
        parts.queryItems=[URLQueryItem(name:"subject",value:"Vigil problem · "+version),URLQueryItem(name:"body",value:"What happened?\n\nDevice: "+ProcessInfo.processInfo.operatingSystemVersionString+"\nVersion: "+version+"\n\nPlease check this message before sending. Don't include keys or private screen content.")]
        return parts.url!
    }
}
