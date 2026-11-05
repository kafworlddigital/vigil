"""Source guard alongside native cloud builds; never a substitute for hardware acceptance."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
frame=(root/'App/VoiceVision/VigilTiredFrame.swift').read_text()
assert 'VNDetectFaceLandmarksRequest' in frame and 'VNDetectHumanBodyPoseRequest' in frame
assert 'AVCaptureVideoDataOutput' in frame
for forbidden in ['URLSession', 'URLRequest', 'write(to:', 'AVCaptureMovieFileOutput', 'for: .audio']:
    assert forbidden not in frame, forbidden
controller=(root/'App/VoiceVision/VigilSupportController.swift').read_text()
assert 'coverOpen, isEnabled("tired")' in controller
assert 'now.timeIntervalSince(tiredAt) >= 300' in controller
assert '300' in (root/'Core/SupportPolicy.swift').read_text()
intro=(root/'App/VoiceVision/VigilFeatureViews.swift').read_text()
for title in ['Vigil, I’m stuck', 'Remind me in a few minutes', 'Meeting in 5 minutes', 'A little break', 'A private tired check']:
    assert title in intro, title
assert '"opencode-go"' not in (root/'Core/ModelHealthRouter.swift').read_text().split('public var freeForQuestions: Bool',1)[1].split('public struct ModelHealth',1)[0]
print('Support feature privacy, frequency, free routing and onboarding source guards passed.')
