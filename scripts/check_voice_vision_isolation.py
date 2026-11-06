"""Small source/configuration guard; native compilation remains a separate CI gate."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
project = (root / 'project.yml').read_text()
targets = project.split('targets:\n', 1)[1].split('schemes:\n', 1)[0]
for name in ['Vigil', 'VigilMac', 'VigilMacy', 'VigilMacyMac']:
    match = re.search(r'^  ' + name + r':\n(.*?)(?=^  \w+:\n|\Z)', targets, re.M | re.S)
    assert match, name
    block = match.group(1)
    if 'Macy' in name:
        assert 'VIGIL_VOICE_VISION VIGIL_MACY' in block
        assert '- VoiceVision' not in block, name
        assert 'CFBundleDisplayName: Vigil for Macy' in block
        assert 'NSCameraUsageDescription:' in block
        if name == 'VigilMacy':assert 'Config/VigilMacy.entitlements' in block
    else:
        assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) VIGIL_VOICE_VISION' in block, name
        assert 'NSCameraUsageDescription:' in block
for path in (root / 'App/VoiceVision').glob('*.swift'):
    assert path.read_text().startswith('#if VIGIL_VOICE_VISION'), path
for name in ['VigilMacy.entitlements','VigilMacyMac.entitlements']:
    assert 'tuck' not in (root/'Config'/name).read_text().lower()
bridge=(root/'Core/TuckKeychainBridge.swift').read_text()
assert '#if VIGIL_MACY\n        return 0\n        #else' in bridge
assert 'if !VigilEdition.macy && reply.local' in (root/'App/VigilAI.swift').read_text()
print('Both Macy feature targets, separate entitlements and compile-time Tuck exclusion passed.')
