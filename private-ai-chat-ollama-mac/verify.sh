#!/bin/bash
# Machine checks for the Ollama install. Prints ALL CHECKS PASSED or the first failing check.
# No accounts exist in this setup, so there is no login check; the "real task" is one chat per model.
set -uo pipefail

PINNED_VERSION="${PINNED_VERSION:-0.40.16}"
MODELS=(gemma3:1b qwen3.5:2b-q4_K_M llama3.2:3b)
API="http://127.0.0.1:11434"
MIN_FREE_GB=20

n=0
check() { n=$((n + 1)); local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok $n  $name"; else echo "FAILED check $n: $name"; exit 1; fi; }

ver_ok()      { ollama -v 2>/dev/null | grep -q "$PINNED_VERSION"; }
api_ok()      { curl -fsS --max-time 5 "$API/api/version" | grep -q "\"$PINNED_VERSION\""; }
local_only()  { local l; l="$(lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
                [[ -n "$l" ]] && ! grep -Eqv '^(127\.0\.0\.1|\[::1\]):11434$' <<<"$l"; }
disk_ok()     { (( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )); }
models_ok()   { local tags; tags="$(curl -fsS "$API/api/tags")" || return 1
                for m in "${MODELS[@]}"; do grep -q "\"name\":\"$m\"" <<<"$tags" || return 1; done; }
chat_ok() {   # one real answer, fixed seed, thinking off so every model is compared the same way
  /usr/bin/python3 - "$API" "$1" <<'PY'
import json, sys, urllib.request
api, model = sys.argv[1], sys.argv[2]
def post(path, body):
    req = urllib.request.Request(api + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))
body = {"model": model, "stream": False,
        "prompt": "What is 17 plus 25? Reply with the number only.",
        "options": {"temperature": 0, "seed": 1, "num_predict": 16}}
if "thinking" in post("/api/show", {"model": model}).get("capabilities", []):
    body["think"] = False          # only models that can think accept the switch
r = post("/api/generate", body)
sys.exit(0 if "42" in r.get("response", "") else 1)
PY
}

check "ollama CLI is version $PINNED_VERSION"          ver_ok
check "server answers on 127.0.0.1:11434"              api_ok
check "server listens on localhost only"               local_only
check "all ${#MODELS[@]} models are installed"          models_ok
for m in "${MODELS[@]}"; do
  check "$m answers a chat (17 + 25 = 42)"             chat_ok "$m"
  ollama stop "$m" >/dev/null 2>&1 || true
done
check "at least $MIN_FREE_GB GB of disk still free"   disk_ok

echo "ALL CHECKS PASSED"
