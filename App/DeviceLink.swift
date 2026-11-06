import SwiftUI
import Network
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

enum VigilPairing {
    static var service:String {VigilEdition.keyPrefix+".pairing"}
    static func save(_ record:PairingRecord) throws {
        let data=try JSONEncoder().encode(record)
        try KeyVault.write(data.base64EncodedString(),service:service,account:"paired-mac")
    }
    static func load()->PairingRecord? {
        guard let value=KeyVault.read(service:service,account:"paired-mac"),let data=Data(base64Encoded:value) else { return nil }
        return try? JSONDecoder().decode(PairingRecord.self,from:data)
    }
    #if os(macOS)
    static func macRecord()->PairingRecord? {
        if let saved=load() { return saved }
        let key=SymmetricKey(size:.bits256).withUnsafeBytes{Data($0)}
        let record=PairingRecord(service:Host.current().localizedName ?? "Mac",secret:key)
        do { try save(record);return record } catch { return nil }
    }
    #endif
}
#if os(macOS)
final class MacDeviceServer:ObservableObject {
    @Published var phones:[String]=[]
    @Published var message=""
    let pairing=VigilPairing.macRecord()
    var onPacket:((Packet,@escaping(Packet)->Void)->Void)?
    private var listener:NWListener?
    private var links:[ObjectIdentifier:LineConnection]=[:]
    private var names:[ObjectIdentifier:String]=[:]
    func start() {
        guard listener==nil,let pairing,let key=pairing.key else { return }
        do {
            let listener=try NWListener(using:.googly)
            listener.service=NWListener.Service(name:pairing.service,type:VigilEdition.bonjour,txtRecord:NWTXTRecord(["vigil-id":pairing.identifier]))
            listener.newConnectionHandler={ [weak self] connection in
                guard let self else { return }
                let link=LineConnection(connection,secret:key,server:true),id=ObjectIdentifier(connection)
                self.links[id]=link
                link.onAuthenticated={ [weak self,weak link] in
                    guard let self,let link else { return }
                    self.names[id]="Companion";self.phones=Array(self.names.values)
                    link.send(Packet(hello:pairing.service));self.onPacket?(Packet(command:"focusSync")){link.send($0)}
                }
                link.onPacket={ [weak self,weak link] packet in
                    if let hello=packet.hello { self?.names[id]=hello;self?.phones=Array(self?.names.values ?? Dictionary<ObjectIdentifier,String>().values) }
                    self?.onPacket?(packet){link?.send($0)}
                }
                link.onState={ [weak self] state in
                    switch state {
                    case .failed,.cancelled:self?.links[id]=nil;self?.names[id]=nil;self?.phones=Array(self?.names.values ?? Dictionary<ObjectIdentifier,String>().values)
                    default:break
                    }
                }
                link.start()
            }
            listener.stateUpdateHandler={ [weak self] state in
                if case .failed=state {
                    self?.message="Local pairing is waiting for Wi-Fi."
                    self?.listener?.cancel();self?.listener=nil
                    DispatchQueue.main.asyncAfter(deadline:.now()+5){self?.start()}
                }
            }
            self.listener=listener;listener.start(queue:.main)
        } catch { message="Couldn't start local pairing. Please reopen Vigil." }
    }
    func broadcast(_ packet:Packet) { for link in links.values { link.send(packet) } }
}
#else
final class PhoneDeviceLink:ObservableObject {
    let face=FaceAnimator()
    @Published var nudge=""
    @Published var state=VigilState()
    @Published var connected=false
    @Published var fresh=false
    @Published var message="Pair your Mac to begin."
    private var browser:NWBrowser?
    private var link:LineConnection?
    private var retry:DispatchWorkItem?
    private var timer:Timer?
    private var receivedAt=Date.distantPast
    private var outbox:[ParkedIdea]=[]
    private var outboxFile:URL { file.deletingLastPathComponent().appendingPathComponent("parked-outbox.json") }
    private var file:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(VigilEdition.folder+"/summary.json") }
    init() {
        if let data=try? Data(contentsOf:file),let saved=try? JSONDecoder().decode(VigilState.self,from:data){state=saved}
        if let data=try? Data(contentsOf:outboxFile),let saved=try? JSONDecoder().decode([ParkedIdea].self,from:data){outbox=saved}
    }
    func start() {
        guard browser==nil else { return }
        let browser=NWBrowser(for:.bonjourWithTXTRecord(type:VigilEdition.bonjour,domain:nil),using:.googly)
        browser.browseResultsChangedHandler={ [weak self] _,_ in self?.connect() }
        browser.stateUpdateHandler={ [weak self] state in if case .failed=state { self?.stop();self?.scheduleRetry() } }
        self.browser=browser;browser.start(queue:.main)
        timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true){[weak self] _ in
            guard let self else { return }
            self.fresh=self.connected && Date().timeIntervalSince(self.receivedAt)<15
            if self.connected { self.link?.send(Packet(command:"focusPing")) }
        }
    }
    func stop() { retry?.cancel();timer?.invalidate();timer=nil;browser?.cancel();browser=nil;link?.cancel();link=nil;connected=false;fresh=false }
    private func scheduleRetry() {
        retry?.cancel();let work=DispatchWorkItem{[weak self] in if self?.browser==nil { self?.start() } else { self?.connect() } };retry=work
        DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    private func connect() {
        guard link==nil,let pairing=VigilPairing.load(),let key=pairing.key,
            let result=browser?.browseResults.first(where:{ result in
                guard case .bonjour(let txt)=result.metadata else { return false }
                return txt.getEntry(for:"vigil-id") == .string(pairing.identifier)
            }) else { return }
        let link=LineConnection(NWConnection(to:result.endpoint,using:.googly),secret:key,server:false)
        self.link=link
        link.onAuthenticated={ [weak self,weak link] in
            self?.connected=true;self?.message="Your Mac is connected."
            link?.send(Packet(hello:UIDevice.current.name));link?.send(Packet(command:"focusSync"))
        }
        link.onPacket={ [weak self] packet in
            guard let self else { return }
            if packet.command=="focusState",let text=packet.text,let incoming=try? JSONDecoder().decode(VigilState.self,from:Data(text.utf8)) {
                self.outbox.removeAll{idea in incoming.ideas.contains(where:{$0.id==idea.id})}
                self.state=incoming
                for idea in self.outbox where !self.state.ideas.contains(where:{$0.id==idea.id}) {self.state.ideas.append(idea)}
                self.fresh=true;self.receivedAt=Date();self.saveOutbox();self.flushOutbox()
                try? FileManager.default.createDirectory(at:self.file.deletingLastPathComponent(),withIntermediateDirectories:true)
                if let data=try? JSONEncoder().encode(self.state){try? data.write(to:self.file,options:.atomic)}
            }
            if let face=packet.face { self.face.receive(face,at:Date.timeIntervalSinceReferenceDate) }
            if packet.command=="nudge",let text=packet.text {
                self.message=text;self.nudge=text;self.face.localMood = .surprised
                #if VIGIL_VOICE_VISION
                if CompanionPreferences().nudge != .quiet { VigilFeedback.nudge() }
                #else
                VigilChirp.shared.play()
                #endif
                Task { @MainActor in VigilAI.shared.postNotification(text) }
                DispatchQueue.main.asyncAfter(deadline:.now()+8){[weak self] in self?.nudge="";self?.face.localMood=nil}
            }
        }
        link.onState={ [weak self,weak link] state in
            guard let self,link===self.link else { return }
            switch state {
            case .failed,.cancelled:self.connected=false;self.fresh=false;self.link=nil;self.message="Waiting for your Mac on the same Wi-Fi.";self.scheduleRetry()
            default:break
            }
        }
        link.start()
    }
    func pair(_ text:String)->Bool {
        guard let record=PairingRecord.parse(text) else { message="That isn't a Vigil pairing code.";return false }
        do { try VigilPairing.save(record);stop();start();return true }
        catch { message="Couldn't save the pairing securely.";return false }
    }
    private func saveOutbox(){
        try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let data=try? JSONEncoder().encode(outbox){try? data.write(to:outboxFile,options:.atomic)}
        if let data=try? JSONEncoder().encode(state){try? data.write(to:file,options:.atomic)}
    }
    private func flushOutbox(){
        guard connected,fresh else{return}
        for idea in outbox {
            if let data=try? JSONEncoder().encode(idea){link?.send(Packet(command:"focusParkRecord",text:String(data:data,encoding:.utf8)))}
        }
    }
    func send(_ command:String,text:String?=nil) {
        if command=="focusPark",let text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            let idea=ParkedIdea(text:text);outbox.append(idea);state.ideas.append(idea)
            state.notice=connected ? "Parked for Sunday. Back to your task?":"Saved on this device. Your Mac will add it to iCloud when you reconnect."
            saveOutbox();flushOutbox();return
        }
        guard connected,fresh else { message="Connect your paired Mac first.";return }
        link?.send(Packet(command:command,text:text))
    }
}
struct VigilQRScanner:UIViewControllerRepresentable {
    var scanned:(String)->Void
    func makeUIViewController(context:Context)->ScannerController { let vc=ScannerController();vc.scanned=scanned;return vc }
    func updateUIViewController(_ vc:ScannerController,context:Context){}
    static func dismantleUIViewController(_ vc:ScannerController,coordinator:()){vc.stop()}
}
final class ScannerController:UIViewController,AVCaptureMetadataOutputObjectsDelegate {
    var scanned:((String)->Void)?
    private let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"com.kafworlddigital.vigil.qr")
    private var stopped=false
    private var preview:AVCaptureVideoPreviewLayer?
    override func viewDidLoad(){
        super.viewDidLoad()
        if VigilEdition.macy && AVCaptureDevice.authorizationStatus(for:.video) != .authorized {
            let label=UILabel();label.text="Pair with your Mac\n\nAllow your camera once to scan its private code. The camera turns off when you finish.";label.numberOfLines=0;label.textAlignment = .center
            let button=UIButton(type:.system);button.setTitle("Allow Camera",for:.normal);button.addTarget(self,action:#selector(allowPairCamera),for:.touchUpInside)
            let card=UIStackView(arrangedSubviews:[label,button]);card.axis = .vertical;card.spacing=18;card.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(card)
            NSLayoutConstraint.activate([card.centerXAnchor.constraint(equalTo:view.centerXAnchor),card.centerYAnchor.constraint(equalTo:view.centerYAnchor),card.widthAnchor.constraint(lessThanOrEqualTo:view.widthAnchor,constant:-32)])
        } else {allowPairCamera()}
    }
    @objc private func allowPairCamera(){AVCaptureDevice.requestAccess(for:.video){[weak self] granted in DispatchQueue.main.async{if granted,self?.stopped==false{self?.view.subviews.forEach{$0.removeFromSuperview()};self?.configure()}}}}
    private func configure(){
        guard let camera=AVCaptureDevice.default(for:.video),let input=try? AVCaptureDeviceInput(device:camera),session.canAddInput(input) else{return}
        session.addInput(input);let output=AVCaptureMetadataOutput();guard session.canAddOutput(output) else{return}
        session.addOutput(output);output.setMetadataObjectsDelegate(self,queue:.main);output.metadataObjectTypes=[.qr]
        let layer=AVCaptureVideoPreviewLayer(session:session);layer.videoGravity = .resizeAspectFill;view.layer.addSublayer(layer);preview=layer
        queue.async{[session] in session.startRunning()}
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();preview?.frame=view.bounds}
    func stop(){stopped=true;queue.async{[session] in session.stopRunning()}}
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput objects:[AVMetadataObject],from connection:AVCaptureConnection){
        guard !stopped,let text=(objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,PairingRecord.parse(text) != nil else{return}
        stop();scanned?(text)
    }
}
#endif
