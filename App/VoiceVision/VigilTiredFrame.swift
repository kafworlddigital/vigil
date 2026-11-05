#if VIGIL_VOICE_VISION
import Foundation
import AVFoundation
import Vision
import CoreVideo
import ImageIO

/// One in-memory video frame. No file output, audio input, encoder or networking.
/// Configuration/shutdown and Vision run serially away from the main thread.
final class VigilTiredFrame: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Observation: Sendable { case covered, clear, cue }
    private let queue = DispatchQueue(label: "com.kafworlddigital.vigil.single-frame")
    private let frames = DispatchQueue(label: "com.kafworlddigital.vigil.single-frame.delivery")
    private lazy var session = AVCaptureSession()
    private var continuation: CheckedContinuation<Observation, Error>?
    private var cancelled = false
    private var taken = false
    func check() async throws -> Observation {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    self.session.beginConfiguration()
                    do {
                        self.session.sessionPreset = .low
                        #if os(iOS)
                        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                        #else
                        let camera = AVCaptureDevice.default(for: .video)
                        #endif
                        guard let camera else { throw FrameError.unavailable }
                        let input = try AVCaptureDeviceInput(device: camera)
                        guard self.session.canAddInput(input) else { throw FrameError.unavailable }
                        self.session.addInput(input)
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.setSampleBufferDelegate(self, queue: self.frames)
                        guard self.session.canAddOutput(output) else { throw FrameError.unavailable }
                        self.session.addOutput(output); self.session.commitConfiguration()
                        self.session.startRunning()
                        self.queue.asyncAfter(deadline: .now() + 4) {
                            if self.continuation != nil { self.finish(.failure(FrameError.unavailable)) }
                        }
                    } catch {
                        self.session.commitConfiguration(); self.finish(.failure(error))
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() {
        queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        queue.async {
            guard !self.taken, !self.cancelled, self.continuation != nil else { return }
            self.taken = true
            // The delivery callback returns before shutdown, avoiding a capture queue deadlock.
            self.session.stopRunning()
            do { self.finish(.success(try Self.inspect(pixel))) }
            catch { self.finish(.failure(error)) }
        }
    }
    private func finish(_ result: Result<Observation, Error>) {
        if session.isRunning { session.stopRunning() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: cancelled ? .failure(CancellationError()) : result)
    }
    private static func inspect(_ pixel: CVPixelBuffer) throws -> Observation {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        var brightness: Double = 0, count: Double = 0
        if let base = CVPixelBufferGetBaseAddress(pixel) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel), stride = CVPixelBufferGetBytesPerRow(pixel)
            for y in Swift.stride(from: 0, to: height, by: 12) {
                for x in Swift.stride(from: 0, to: width, by: 12) {
                    let p = y * stride + x * 4
                    brightness += Double(bytes[p]) * 0.0722 + Double(bytes[p + 1]) * 0.7152 + Double(bytes[p + 2]) * 0.2126
                    count += 1
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
        guard count > 0, brightness / count > 18 else { return .covered }
        let faces = VNDetectFaceLandmarksRequest()
        let body = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
        try handler.perform([faces, body])
        // Multiple people or no reliable landmarks do not count as a tired cue.
        guard let observations = faces.results, observations.count == 1,
              let face = observations.first, face.confidence >= 0.75, let landmarks = face.landmarks else { return .clear }
        func ratio(_ region: VNFaceLandmarkRegion2D?) -> CGFloat? {
            guard let region, region.pointCount >= 4 else { return nil }
            let points = region.normalizedPoints
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0.001 else { return nil }
            return (maxY - minY) / (maxX - minX)
        }
        let mouthOpen = (ratio(landmarks.innerLips) ?? 0) > 0.65
        let eyesClosed: Bool
        if let left = ratio(landmarks.leftEye), let right = ratio(landmarks.rightEye) { eyesClosed = left < 0.12 && right < 0.12 }
        else { eyesClosed = false }
        var slumped = false
        if let pose = body.results?.first,
           let neck = try? pose.recognizedPoint(.neck), let nose = try? pose.recognizedPoint(.nose),
           let left = try? pose.recognizedPoint(.leftShoulder), let right = try? pose.recognizedPoint(.rightShoulder),
           [neck, nose, left, right].allSatisfy({ $0.confidence > 0.6 }) {
            let shoulders = hypot(left.location.x - right.location.x, left.location.y - right.location.y)
            slumped = shoulders > 0.1 && nose.location.y - neck.location.y < shoulders * 0.08
        }
        return mouthOpen || eyesClosed || slumped ? .cue : .clear
    }
    private enum FrameError: Error { case unavailable }
}
#endif
