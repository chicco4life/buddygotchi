#!/bin/sh
# Two headless launches over the USB link to fakedev.py, the second 3 s
# after the first stops, so the fake device still counts the app as there
# and says no hello unasked. Each forces a proud reaction and waits for its
# ended. Run from the repo root after `make build`.
set -e
out=$(cd "$(dirname "$0")" && pwd)
dir=/tmp/boop-hu-$$
mkdir -p "$dir"
python3 "$out/fakedev.py" "$dir/dev.sock" 1aace295d219 &
fake=$!
sleep 0.5
launch() {
  .build/debug/Boop --headless --state-dir "$dir/state" --link "usb:$dir/dev.sock" --brain scripted --debug \
    > "$out/launch$1.out" 2>&1 &
  boop=$!
  sleep 1.5
  python3 - "$dir/state/boop.sock" <<'EOF'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(b'{"dev":"answer","answers":{"react.mood":"proud","react.loops":"twice","say.feeling":"glad","say.kind":"phrase"}}\n')
s.close()
EOF
  sleep 2.5
  kill -TERM $boop
  wait $boop || true
}
launch 1
sleep 3
launch 2
kill $fake
cp "$dir/state/boop.log" "$dir/state/debug.jsonl" "$out/"
cp "$dir/state/debug.1.jsonl" "$out/"
echo "state dir: $dir/state"
