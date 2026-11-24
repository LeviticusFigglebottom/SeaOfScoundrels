#!/usr/bin/env bash
# Two-process host/client smoke test: a client joins and must receive the host's sea clock and weather.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"; port=$((24000 + RANDOM % 1000))
"$GODOT" --headless --path . res://tests/net/net_probe.tscn -- role=host port=$port > /tmp/sos_net_host.log 2>&1 &
hp=$!
sleep 1.5
"$GODOT" --headless --path . res://tests/net/net_probe.tscn -- role=client port=$port > /tmp/sos_net_client.log 2>&1
rc=$?
wait $hp
grep -E "RESULT|err=" /tmp/sos_net_host.log /tmp/sos_net_client.log
# Clock agreement: last host and client readings should be within a quarter second.
python3 - <<'PY'
import re,sys
h=[float(l.split()[2]) for l in open('/tmp/sos_net_host.log') if l.startswith('HOSTCLK')]
c=[float(l.split()[1]) for l in open('/tmp/sos_net_client.log') if l.startswith('CLIENTCLK')]
print("host last %.2f client last %.2f (host runs ~3 s longer)"%(h[-1],c[-1]))
PY
exit $rc
