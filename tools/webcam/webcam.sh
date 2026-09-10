#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build="$root/.build/webcam"
mkdir -p "$build"
if [ ! -x "$build/webcam" ] || [ "$root/tools/webcam/Webcam.swift" -nt "$build/webcam" ] || [ "$root/tools/webcam/Info.plist" -nt "$build/webcam" ]; then
    xcrun swiftc -swift-version 5 "$root/tools/webcam/Webcam.swift" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$root/tools/webcam/Info.plist" -o "$build/webcam"
fi
exec "$build/webcam" "$@"
