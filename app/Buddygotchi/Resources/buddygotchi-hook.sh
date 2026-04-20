#!/bin/bash
SOURCE="${1:-claude-code}"
CFG="$HOME/.buddygotchi/config.json"
PORT=$(grep -o '"port" *: *[0-9]*' "$CFG" 2>/dev/null | grep -o '[0-9]*')
curl -s -o /dev/null --noproxy '*' \
  -X POST "http://127.0.0.1:${PORT}/hook/event?source=${SOURCE}&pid=$$" \
  -H "Content-Type: application/json" \
  -d "$(cat)" \
  --connect-timeout 1 2>/dev/null || true
exit 0
