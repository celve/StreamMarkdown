#!/bin/bash
# LIN-2404's run on the shared iPhone Duo: streams the 10k-character answer at 24 characters every 50 ms, then scrolls
# it, `runs` times, and prints the PERF lines; arguments after `runs` go to the app, such as `-render 0` for the floor.
# usage: [CONFIGURATION=Release] scripts/perf.sh <issue> [runs] [launch arguments…]
set -u
cd "$(dirname "$0")/.."
issue=${1:?usage: scripts/perf.sh <issue> [runs]}
runs=${2:-2}
shift $(( $# < 2 ? $# : 2 ))
id=com.celve.streammarkdown.demo.$(echo "$issue" | tr '[:upper:]' '[:lower:]')
app=$(scripts/demo.sh "$id") || exit 1
duo=${DUO_SIM:-$HOME/.skills/skills/duo-sim/duo-sim.sh}
udid=$("$duo" acquire "$issue" --app "$id") || exit 1
xcrun simctl install "$udid" "$app"
xcrun simctl ui "$udid" appearance light
for r in $(seq 1 "$runs"); do
  echo "== ${CONFIGURATION:-Debug} run $r $* $(date +%T) load $(sysctl -n vm.loadavg)"
  xcrun simctl terminate "$udid" "$id" 2>/dev/null
  perl -e 'alarm shift; exec @ARGV' 150 xcrun simctl launch --console-pty "$udid" "$id" -stream 1 -long 1 -speed 24 -perf 1 "$@" 2>&1 | grep --line-buffered '^PERF'
done
"$duo" release "$issue"
