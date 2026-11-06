#if VIGIL_VOICE_VISION
import Foundation
import AVFoundation
import Speech
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Session setup, recording and shutdown are serialised off the main thread.
/// Caller owns the temporary directory and removes it on every completion path.
final class VigilCameraCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kafworlddigital.vigil.requested-camera")
    private lazy var session = AVCaptureSession()
    private lazy var movie = AVCaptureMovieFileOutput()
    private var continuation: CheckedContinuation<URL, Error>?
    private var cancelled = false
    private var recordingURL: URL?

    func record(to url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation; self.recordingURL = url
                    var configuring = false
                    do {
                        self.session.beginConfiguration()
                        configuring = true
                        self.session.sessionPreset = .medium
                        #if os(iOS)
                        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                        #else
                        let camera = AVCaptureDevice.default(for: .video)
                        #endif
                        guard let camera, let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraFailure.unavailable }
                        for device in [camera, microphone] {
                            let input = try AVCaptureDeviceInput(device: device)
                            guard self.session.canAddInput(input) else { throw CameraFailure.unavailable }
                            self.session.addInput(input)
                        }
                        guard self.session.canAddOutput(self.movie) else { throw CameraFailure.unavailable }
                        self.session.addOutput(self.movie); self.session.commitConfiguration(); configuring = false
                        #if os(iOS)
                        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [])
                        try AVAudioSession.sharedInstance().setActive(true)
                        #endif
                        self.session.startRunning()
                        self.movie.maxRecordedDuration = CMTime(seconds: 4, preferredTimescale: 600)
                        self.movie.startRecording(to: url, recordingDelegate: self)
                        // Also bounds failure to start, not just successful movie duration.
                        self.queue.asyncAfter(deadline: .now() + 7) {
                            guard self.continuation != nil else { return }
                            if self.movie.isRecording { self.movie.stopRecording() }
                            self.finish(.failure(CameraFailure.timeout))
                        }
                    } catch {
                        if configuring { self.session.commitConfiguration() }
                        if self.session.isRunning { self.session.stopRunning() }
                        self.finish(.failure(error))
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() {
        queue.async {
            self.cancelled = true
            guard self.continuation != nil else { return }
            if self.session.isRunning {
                self.movie.stopRecording(); self.session.stopRunning()
                // didFinish closes the movie before resuming; the seven-second watchdog bounds a missing callback.
            } else { self.finish(.failure(CancellationError())) }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            if self.cancelled { self.finish(.failure(CancellationError())); return }
            if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                self.finish(.failure(error))
            } else { self.finish(.success(outputFileURL)) }
        }
    }
    private func finish(_ result: Result<URL, Error>) {
        // Camera/microphone hardware stops before the awaiting caller receives any frames.
        if session.isRunning { session.stopRunning() }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        guard let continuation else { return }
        self.continuation = nil; continuation.resume(with: result)
    }
    enum CameraFailure: Error { case unavailable, timeout }

    /// Three small frames become one contact sheet; raw video/audio is never uploaded.
    static func contactSheet(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 3, duration <= 5.5 else { throw CameraFailure.unavailable }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 384, height: 384)
        guard let context = CGContext(data: nil, width: 1152, height: 384, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CameraFailure.unavailable }
        for (index, fraction) in [0.15, 0.5, 0.85].enumerated() {
            try Task.checkCancellation()
            let (frame, _) = try await generator.image(at: CMTime(seconds: duration * fraction, preferredTimescale: 600))
            let scale = min(384 / CGFloat(frame.width), 384 / CGFloat(frame.height))
            let width = CGFloat(frame.width) * scale, height = CGFloat(frame.height) * scale
            context.draw(frame, in: CGRect(x: CGFloat(index) * 384 + (384 - width) / 2, y: (384 - height) / 2, width: width, height: height))
        }
        guard let image = context.makeImage() else { throw CameraFailure.unavailable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw CameraFailure.unavailable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraFailure.unavailable }
        return data as Data
    }
    @MainActor static func question(from url: URL) async -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: VigilEdition.macy ? "en-US" : "en-GB")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return "" }
        let job = CameraTranscription(recognizer: recognizer, url: url)
        return await job.run()
    }
}

@MainActor private final class CameraTranscription {
    let recognizer: SFSpeechRecognizer
    let url: URL
    private var continuation: CheckedContinuation<String, Never>?
    private var task: SFSpeechRecognitionTask?
    private var deadline: Task<Void, Never>?
    init(recognizer: SFSpeechRecognizer, url: URL) { self.recognizer = recognizer; self.url = url }
    func run() async -> String {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { complete(""); return }
                let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = true
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor in
                        if let result, result.isFinal { self?.complete(result.bestTranscription.formattedString) }
                        else if error != nil { self?.complete("") }
                    }
                }
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                    self?.complete("")
                }
            }
        } onCancel: { Task { @MainActor in self.complete("") } }
    }
    private func complete(_ text: String) {
        guard let continuation else { return }
        self.continuation = nil
        let recognition = task; task = nil; deadline?.cancel(); deadline = nil
        recognition?.cancel(); continuation.resume(returning: String(text.prefix(500)))
    }
}
#endif
