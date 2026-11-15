#!/bin/bash
# Machine checks for this episode's setup. Prints ALL CHECKS PASSED or the first failing check.
# Ollama has no accounts, so there is no login check; the real tasks are a chat answer and a context change
# that shows up in the server's own memory report (/api/ps).
set -uo pipefail

PINNED_VERSION="${PINNED_VERSION:-0.40.16}"
MODEL="gemma3:1b"
API="http://127.0.0.1:11434"
MIN_FREE_GB=20

n=0; ERR="$(mktemp)"
check() { n=$((n + 1)); local name="$1"; shift
  if "$@" >/dev/null 2>"$ERR"; then echo "ok $n  $name"
  else echo "FAILED check $n: $name"; sed 's/^/  /' "$ERR"; rm -f "$ERR"; exit 1; fi; }
py() { /usr/bin/python3 - "$API" "$MODEL" "$@"; }

ver_ok()     { ollama -v 2>/dev/null | grep -q "$PINNED_VERSION"; }
api_ok()     { curl -fsS --max-time 5 "$API/api/version" | grep -q "\"$PINNED_VERSION\""; }
local_only() { local l; l="$(lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
               [[ -n "$l" ]] && ! grep -Eqv '^(127\.0\.0\.1|\[::1\]):11434$' <<<"$l"; }
no_login()   { [[ ! -e "$HOME/Library/LaunchAgents/homebrew.mxcl.ollama.plist" ]]; }
model_ok()   { curl -fsS "$API/api/tags" | grep -q "\"name\":\"$MODEL\""; }
disk_ok()    { (( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )); }
unload_all() { for m in $(curl -fsS "$API/api/ps" | /usr/bin/python3 -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin)["models"]))'); do
                 ollama stop "$m"; done; }

# One real answer (fixed seed), then the loaded entry in /api/ps must match the request.
#   py <num_ctx> <expect_ctx>: answers 42, context_length == expect_ctx, 100% on the GPU; prints the loaded size.
ctx_task() {
  py "$1" "$2" <<'PY'
import json, sys, urllib.request
api, model, num_ctx, want = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
def call(path, body=None):
    req = urllib.request.Request(api + path, json.dumps(body).encode() if body else None,
                                 {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))
body = {"model": model, "stream": False, "prompt": "What is 17 plus 25? Reply with the number only.",
        "options": {"temperature": 0, "seed": 1, "num_predict": 16}}
if num_ctx: body["options"]["num_ctx"] = num_ctx
r = call("/api/generate", body)
if "42" not in r.get("response", ""): sys.exit(f"answer was {r.get('response')!r}")
m = [m for m in call("/api/ps")["models"] if m["name"] == model]
if not m: sys.exit("model not loaded after the request")
m = m[0]
if m.get("context_length") != want: sys.exit(f"context_length {m.get('context_length')}, expected {want}")
if m["size_vram"] != m["size"]: sys.exit(f"not 100% GPU: {m['size_vram']} of {m['size']} bytes on the GPU")
open(f"/tmp/verify-size-{want}", "w").write(str(m["size"]))
PY
}
default_ctx()  { unload_all; ctx_task 0 4096; }
bigger_ctx()   { ollama stop "$MODEL"; ctx_task 8192 8192 &&
                 (( $(cat /tmp/verify-size-8192) > $(cat /tmp/verify-size-4096) )); }

check "ollama CLI is version $PINNED_VERSION"                         ver_ok
check "server answers on 127.0.0.1:11434"                             api_ok
check "server listens on localhost only"                              local_only
check "no login item or background service registered for ollama"    no_login
check "$MODEL is installed"                                           model_ok
check "$MODEL answers (17 + 25 = 42) at the default context 4096, 100% GPU"   default_ctx
check "num_ctx 8192 per request: /api/ps shows 8192 and a bigger loaded size"  bigger_ctx
check "at least $MIN_FREE_GB GB of disk still free"                   disk_ok
ollama stop "$MODEL" >/dev/null 2>&1 || true
echo "loaded size of $MODEL: $(cat /tmp/verify-size-4096) bytes at 4096, $(cat /tmp/verify-size-8192) bytes at 8192"
rm -f /tmp/verify-size-4096 /tmp/verify-size-8192 "$ERR"

echo "ALL CHECKS PASSED"
