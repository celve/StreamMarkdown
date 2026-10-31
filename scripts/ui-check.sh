#!/bin/bash
# Runs the demo's UI checks on the shared iPhone Duo in light and dark appearance, saving screenshots to <shots dir>
# named <check>-<posture>-<appearance>.png. usage: [POSTURE=folded] [ONLY=<test name>] [KEEP=1] scripts/ui-check.sh <issue> <shots dir>
set -u
cd "$(dirname "$0")/.."
issue=${1:?usage: scripts/ui-check.sh <issue> <shots dir>}
shots=${2:?usage: scripts/ui-check.sh <issue> <shots dir>}
mkdir -p "$shots"
id=com.celve.streammarkdown.demo.$(echo "$issue" | tr '[:upper:]' '[:lower:]')
xcodegen generate --spec Demo/project.yml --project Demo --quiet
build=(-project Demo/StreamMarkdownDemo.xcodeproj -scheme StreamMarkdownDemo -derivedDataPath .build/demo-test DEMO_BUNDLE_ID="$id")
xcodebuild build-for-testing "${build[@]}" -destination 'generic/platform=iOS Simulator' -quiet || exit 1
duo=${DUO_SIM:-$HOME/.skills/skills/duo-sim/duo-sim.sh}
udid=$("$duo" acquire "$issue" --app "$id" --app "$id.uitests.xctrunner") || exit 1
for appearance in ${APPEARANCES:-light dark}; do
  xcrun simctl ui "$udid" appearance "$appearance"
  TEST_RUNNER_SHOTS_DIR="$shots" TEST_RUNNER_SHOTS_SUFFIX="-${POSTURE:-folded}-$appearance" \
    xcodebuild test-without-building "${build[@]}" -destination "id=$udid" -parallel-testing-enabled NO \
    -collect-test-diagnostics never ${ONLY:+-only-testing:StreamMarkdownDemoUITests/DemoUITests/$ONLY} 2>&1 |
    grep -E "Test Case .*(passed|failed)|error:|HEADING-SNAPSHOT|\*\* TEST"
done
[ -n "${KEEP:-}" ] || "$duo" release "$issue"
