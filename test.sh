#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${KEYTONE_BUILD_DIR:-.build}"
mkdir -p "$BUILD"
xcrun clang -std=c11 -O1 -g -fsanitize=address,undefined Sources/AudioCore.c Tests/audio_core_test.c -framework AudioToolbox -framework CoreAudio -o "$BUILD/audio_core_test"
"$BUILD/audio_core_test"
xcrun swiftc Sources/PressFilter.swift Tests/Input/main.swift -o "$BUILD/input_test"
"$BUILD/input_test"
python3 scripts/audit_samples.py

xcrun swiftc Sources/Localization.swift Tests/Localization/main.swift -o "$BUILD/localization_test"
"$BUILD/localization_test"
