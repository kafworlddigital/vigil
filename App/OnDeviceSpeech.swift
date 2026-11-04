import SwiftUI
import Speech
import AVFoundation

@MainActor final class OnDeviceSpeech:ObservableObject {
    @Published var listening=false
    @Published var transcript=""
    @Published var message=""
    var onResult:((String)->Void)?
    private var audio:AVAudioEngine?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var recognition:SFSpeechRecognitionTask?
    private var held=false
    private var generation=UUID()
    private var hasTap=false
    func begin() async {
        guard !held else{return};held=true;let token=UUID();generation=token;transcript="";message=""
        let status=await withCheckedContinuation{(c:CheckedContinuation<SFSpeechRecognizerAuthorizationStatus,Never>) in SFSpeechRecognizer.requestAuthorization{c.resume(returning:$0)}}
        guard held,generation==token else{message="Hold again when you’re ready to talk.";return}
        let mic=await AVCaptureDevice.requestAccess(for:.audio)
        guard held,generation==token else{message="Hold again when you’re ready to talk.";return}
        guard status == .authorized,mic else{message="Allow microphone and speech access to hold to talk.";held=false;return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"en-GB")),recognizer.isAvailable,recognizer.supportsOnDeviceRecognition else {
            message="On-device speech isn't available here yet. You can type your task or idea.";held=false;return
        }
        do {
            let audio=AVAudioEngine();self.audio=audio
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record,mode:.measurement,options:.duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let request=SFSpeechAudioBufferRecognitionRequest();request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true;self.request=request
            recognition=recognizer.recognitionTask(with:request){[weak self] result,error in Task{@MainActor in
                guard let self,self.generation==token else{return}
                if let result{self.transcript=result.bestTranscription.formattedString}
                if error != nil,self.held {self.message="I missed that. You can try again or type it.";self.finish()}
            }}
            let input=audio.inputNode,format=input.outputFormat(forBus:0)
            guard format.sampleRate>0,format.channelCount>0 else{throw SpeechFailure.noInput}
            input.installTap(onBus:0,bufferSize:1024,format:format){[weak request] buffer,_ in request?.append(buffer)};hasTap=true
            audio.prepare();try audio.start();listening=true
        } catch { message="Couldn't start the microphone. You can type instead.";held=false;cleanUp() }
    }
    func finish() {
        guard held else{return};held=false
        if audio?.isRunning==true{audio?.stop()};if hasTap{audio?.inputNode.removeTap(onBus:0);hasTap=false};request?.endAudio();listening=false
        let token=generation
        Task{[weak self] in
            try? await Task.sleep(nanoseconds:600_000_000)
            guard let self,self.generation==token,!self.held else{return}
            let result=self.transcript.trimmingCharacters(in:.whitespacesAndNewlines)
            self.cleanUp();self.generation=UUID()
            if !result.isEmpty{self.onResult?(result)}
        }
    }
    func cancel(){held=false;generation=UUID();cleanUp()}
    private func cleanUp(){
        if audio?.isRunning==true{audio?.stop()};if hasTap{audio?.inputNode.removeTap(onBus:0);hasTap=false}
        recognition?.cancel();recognition=nil;request=nil;audio=nil;listening=false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        #endif
    }
    private enum SpeechFailure:Error{case noInput}
}
