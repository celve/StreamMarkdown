#!/bin/bash
# Generates the demo's Xcode project and builds it for the iOS Simulator.
# usage: [CONFIGURATION=Release] scripts/demo.sh [bundle id]   (prints the built .app's path; Debug by default, as LIN-2404 measured)
set -euo pipefail
cd "$(dirname "$0")/.."
config=${CONFIGURATION:-Debug}
xcodegen generate --spec Demo/project.yml --project Demo --quiet
xcodebuild -project Demo/StreamMarkdownDemo.xcodeproj -scheme StreamMarkdownDemo -configuration "$config" \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/demo \
  DEMO_BUNDLE_ID="${1:-com.celve.streammarkdown.demo}" build -quiet >&2
echo "$PWD/.build/demo/Build/Products/$config-iphonesimulator/StreamMarkdownDemo.app"
