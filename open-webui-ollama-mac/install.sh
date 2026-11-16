#!/bin/bash
# Open WebUI (pip, Python 3.12 venv) + Ollama (Homebrew formula) + three small models, on an Apple silicon Mac.
# Idempotent: run it again and it only starts what is stopped. Tested versions are listed in README.md.
# Safe defaults: both servers listen on 127.0.0.1 only; no OpenAI connection; new sign-ups close after the admin.
# Nothing is registered to start at login (no brew services, no launchctl); no sudo.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

MAX_MODEL_BYTES=$((5 * 1000 * 1000 * 1000))       # 5 GB per model (owner cap, T1)
MAX_TOTAL_BYTES=$((6 * 1000 * 1000 * 1000))        # 6 GB for all models (owner cap, T1)
MIN_FREE_GB=20                                     # the Mac keeps 20 GB free
CREATE_ADMIN="${CREATE_ADMIN:-1}"                  # 0: make your own admin in the browser instead

fail() { echo "INSTALL FAILED: $*" >&2; exit 1; }
step() { echo "== $*"; }
T0="$(now)"

# Retry a long download once, then give up (never wait forever). Usage: twice SECONDS command…
twice() { local s="$1"; shift; limit "$s" "$@" || { echo "retrying once: $*"; limit "$s" "$@"; }; }

# 1. Requirements
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || fail "needs an Apple silicon Mac"
(( $(sw_vers -productVersion | cut -d. -f1) >= 14 )) || fail "needs macOS 14 (Sonoma) or newer (Ollama)"
command -v brew >/dev/null || fail "Homebrew not found (https://brew.sh)"
command -v curl >/dev/null || fail "curl not found"
if ! owui_up; then
  lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1 && fail "port 8080 is already in use by another program"
fi
(( $(free_gb) >= MIN_FREE_GB + 12 )) || fail "need $((MIN_FREE_GB + 12)) GB free (models ~5 GB, Open WebUI ~3 GB)"

# 2. Remember how the Mac was found (once), so uninstall.sh can put it back.
save_state

# 3. Ollama, native (Homebrew formula; Metal GPU). Skipped if it is already installed (T1).
step "ollama"
if ! command -v ollama >/dev/null 2>&1; then
  t="$(now)"; twice 900 brew install ollama; echo "brew install ollama: $(since "$t") s"
fi
ver="$(ollama -v 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -1 || true)"
[[ "$ver" == "$OLLAMA_VERSION" ]] || fail "ollama $ver installed, $OLLAMA_VERSION expected (set OLLAMA_VERSION to accept)"
start_ollama || fail "ollama did not answer on $OLLAMA_API (log: $OLLAMA_LOG)"

# 4. Models (explicit tags; size caps checked from the server's own numbers)
step "models"
for m in "${MODELS[@]}"; do
  have_models="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
  if ! grep -qx "$m" <<<"$have_models"; then
    t="$(now)"; twice 1200 ollama pull "$m" >/tmp/ollama-pull.log 2>&1 || { tail -3 /tmp/ollama-pull.log; fail "ollama pull $m"; }
    rm -f /tmp/ollama-pull.log; echo "ollama pull $m: $(since "$t") s"
  fi
done
/usr/bin/python3 - "$OLLAMA_API" "$MAX_MODEL_BYTES" "$MAX_TOTAL_BYTES" "${MODELS[@]}" <<'PY'
import json, sys, urllib.request
api, max_one, max_all, want = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
tags = {m["name"]: m["size"] for m in json.load(urllib.request.urlopen(api + "/api/tags"))["models"]}
missing = [m for m in want if m not in tags]
if missing: sys.exit(f"INSTALL FAILED: models missing: {missing}")
for m in want:
    if tags[m] > max_one: sys.exit(f"INSTALL FAILED: {m} is {tags[m]} bytes (> 5 GB cap)")
total = sum(tags[m] for m in want)
if total > max_all: sys.exit(f"INSTALL FAILED: models total {total} bytes (> 6 GB cap)")
print(f"models total {total/1e9:.2f} GB")
PY

# 5. Python 3.12 (Homebrew). Not 3.13: pip finds no Open WebUI version for it.
step "python 3.12"
if [[ ! -x "$PY" ]]; then
  t="$(now)"; twice 900 brew install "$PY_FORMULA"; echo "brew install $PY_FORMULA: $(since "$t") s"
fi
"$PY" --version | grep -q '^Python 3\.12\.' || fail "$PY is not Python 3.12"

# 6. Open WebUI in its own venv, pinned
step "open-webui $OWUI_VERSION"
if [[ ! -e "$OWUI_HOME" ]]; then                 # only a folder this script creates gets the mark (uninstall.sh)
  mkdir -p "$OWUI_HOME"; date '+%Y-%m-%d' > "$OWUI_MARK"
fi
[[ -x "$VENV/bin/python" ]] || "$PY" -m venv "$VENV"
have="$(owui_installed_version)"
if [[ "$have" != "$OWUI_VERSION" ]]; then
  if owui_up; then stop_owui; fi                   # an upgrade: stop the old server first (back up data/ before!)
  t="$(now)"; twice 1800 "$VENV/bin/pip" install --quiet "open-webui==$OWUI_VERSION"
  echo "pip install open-webui==$OWUI_VERSION: $(since "$t") s"
fi
[[ -x "$VENV/bin/open-webui" ]] || fail "the open-webui command is missing from the venv"
cli_ver="$(owui_installed_version)"
[[ "$cli_ver" == "$OWUI_VERSION" ]] || fail "the venv has open-webui '$cli_ver', not $OWUI_VERSION"

# 7. Start it (first start downloads the document-embedding model from Hugging Face, about 90 MB)
step "start"
t="$(now)"
start_owui 600 || fail "Open WebUI did not answer on $OWUI_URL/health (log: ~/open-webui/logs/serve.log)"
echo "open-webui serve → /health 200: $(since "$t") s"

# 8. The first account becomes the admin. A throwaway local login, saved next to the data (never printed).
if [[ "$CREATE_ADMIN" == 1 && ! -s "$OWUI_LOGIN" ]]; then
  if /usr/bin/python3 - "$OWUI_URL" "$OWUI_LOGIN" <<'PY'
import json, os, secrets, string, sys, urllib.request, urllib.error
url, out = sys.argv[1], sys.argv[2]
cfg = json.load(urllib.request.urlopen(url + "/api/config"))
if not cfg.get("onboarding", False):
    sys.exit(3)                      # users exist already (an earlier run or the browser): nothing to create
pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))
body = {"name": "Demo Admin", "email": "demo@example.com", "password": pw}
req = urllib.request.Request(url + "/api/v1/auths/signup", json.dumps(body).encode(), {"Content-Type": "application/json"})
r = json.load(urllib.request.urlopen(req, timeout=60))
if r.get("role") != "admin":
    sys.exit(f"INSTALL FAILED: first account has role {r.get('role')}, not admin")
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(f"OWUI_EMAIL=demo@example.com\nOWUI_PASSWORD={pw}\n")
PY
  then echo "admin account created; its login is in ~/open-webui/admin-login.txt"
  else rc=$?; [[ $rc == 3 ]] && echo "an account exists already: no admin created" || fail "creating the admin failed"
  fi
fi

(( $(free_gb) >= MIN_FREE_GB )) || fail "less than $MIN_FREE_GB GB free after the install"
echo "installed (open-webui $OWUI_VERSION, ollama $ver, ${#MODELS[@]} models) in $(since "$T0") s: open http://localhost:8080"
