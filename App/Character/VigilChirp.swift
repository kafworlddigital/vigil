#if os(iOS)
import AVFoundation
import Foundation
// Riley Brown's original pentatonic chirp synthesis, without Realtime or microphone capture.
final class VigilChirp {
    static let shared=VigilChirp()
    private var engine:AVAudioEngine?
    private var player:AVAudioPlayerNode?
    private let playFormat=AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
    func play(){
        guard !ProcessInfo.processInfo.arguments.contains("--vigil-proof") else{return}
        let audio=AVAudioSession.sharedInstance()
        try? audio.setCategory(.ambient,options:[.mixWithOthers]);try? audio.setActive(true)
        let engine=AVAudioEngine();let player=AVAudioPlayerNode()
        engine.attach(player);engine.connect(player,to:engine.mainMixerNode,format:playFormat)
        do{try engine.start()}catch{return}
        self.engine=engine;self.player=player
        let syllables=3
        let rate = playFormat.sampleRate
        // C major pentatonic, two octaves up high (C6…E7), so it always sounds sweet together.
        let scale = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0]
        var index = Int.random(in: 1...3)
        var samples: [Float] = []
        for i in 0..<syllables {
            if i > 0 { index = min(max(index + [-1, 1, 1, 2].randomElement()!, 0), scale.count - 1) }
            let note = scale[index] * 0.5  // drop an octave: rounder, less piercing
            let duration = i == syllables - 1 ? 0.13 : Double.random(in: 0.07...0.09)
            let count = Int(duration * rate)
            var phase = 0.0
            for n in 0..<count {
                let time = Double(n) / rate
                let t = Double(n) / Double(count)
                // Scoops up into the note over the first 25 ms, with a gentle wobble on the last one.
                let scoop = 1 - 0.18 * exp(-time / 0.012)
                let wobble = i == syllables - 1 ? 1 + 0.012 * sin(time * 2 * .pi * 18) : 1
                phase += 2 * .pi * note * scoop * wobble / rate
                let attack = min(1, time / 0.006)
                let envelope = attack * exp(-t * 3.2) * (1 - pow(t, 6))
                let wave = sin(phase) + 0.12 * sin(2 * phase)
                samples.append(Float(wave * envelope * 0.26))
            }
            samples += [Float](repeating: 0, count: Int(rate * 0.028))
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: samples.count) }

        player.scheduleBuffer(buffer)
        player.play()
        DispatchQueue.main.asyncAfter(deadline:.now()+1){[weak self] in self?.player?.stop();self?.engine?.stop();self?.player=nil;self?.engine=nil}
    }
}
#endif
