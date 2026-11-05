#!/bin/sh
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
swift test --jobs 2 --filter VigilTests
