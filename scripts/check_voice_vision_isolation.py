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
        assert 'VIGIL_VOICE_VISION' not in block
        assert '- VoiceVision' in block, name
    else:
        assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) VIGIL_VOICE_VISION' in block, name
        assert 'NSCameraUsageDescription:' in block
for path in (root / 'App/VoiceVision').glob('*.swift'):
    assert path.read_text().startswith('#if VIGIL_VOICE_VISION'), path
print('Keith feature conditions and Macy source exclusion passed.')
