"""Require actual native PNG renders; never manufacture evidence on build failure."""
from pathlib import Path
import json, struct, sys
root = Path(sys.argv[1])
receipt = json.loads((root / 'native-feature-previews.json').read_text())
assert receipt['kind'] == 'native SwiftUI cloud preview with synthetic answer fixtures'
assert receipt['cameraCaptured'] is False and receipt['speechPlayed'] is False
expected = ['nudge-chime', 'nudge-bounce', 'nudge-colourFlash', 'nudge-eyeWiggle', 'nudge-spokenLine', 'answer-and-sparkles', 'camera-indicator'] + ['onboarding-' + str(i) for i in range(1, 7)]
for name in expected:
    data = (root / (name + '.png')).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack('>II', data[16:24])
    assert width >= 640 and height >= 400, (name, width, height)
print(f'{len(expected)} native feature view PNGs verified; cloud fixtures, not device or camera acceptance.')
