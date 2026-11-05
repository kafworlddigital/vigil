#!/bin/sh
set -eu
# The XcodeGen project and shared Keith schemes are checked in; no downloads or keys.
cd "$CI_PRIMARY_REPOSITORY_PATH"
test -f Vigil.xcodeproj/project.pbxproj
test -f Vigil.xcodeproj/xcshareddata/xcschemes/VigilMac.xcscheme
test -f Vigil.xcodeproj/xcshareddata/xcschemes/Vigil.xcscheme
python3 scripts/check_voice_vision_isolation.py
python3 scripts/check_support_features.py
