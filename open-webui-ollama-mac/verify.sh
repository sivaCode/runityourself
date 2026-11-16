#!/bin/bash
# Machine checks for Open WebUI + Ollama. Every check is a real request. Prints ALL CHECKS PASSED or the first
# failing check. The login comes from OWUI_EMAIL/OWUI_PASSWORD, else ~/open-webui/admin-login.txt (install.sh's
# throwaway admin), else .state/demo-login.env (the admin made in the browser on camera).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/common.sh"
API_PY=(/usr/bin/python3 "$HERE/lib/owui_api.py")
MIN_FREE_GB=20

if [[ -z "${OWUI_EMAIL:-}" || -z "${OWUI_PASSWORD:-}" ]]; then
  for f in "$OWUI_LOGIN" "$STATE_DIR/demo-login.env"; do
    if [[ -s "$f" ]]; then source "$f"; break; fi
  done
fi
TOKEN_FILE="$(mktemp -t owui-verify)"; trap 'rm -f "$TOKEN_FILE"' EXIT

n=0
check() { n=$((n + 1)); local name="$1"; shift; local out
  if out="$("$@" 2>&1)"; then echo "ok $n  $name${out:+  ($(head -1 <<<"$out" | say_home))}"
  else echo "FAILED check $n: $name${out:+  ($(tail -1 <<<"$out" | say_home))}"; exit 1; fi; }

cli_ver()     { local v; v="$(owui_installed_version)"; [[ -x "$VENV/bin/open-webui" && "$v" == "$OWUI_VERSION" ]] && echo "open-webui $v"; }
venv_py()     { local v; v="$("$VENV/bin/python" --version 2>&1)"; grep -q '^Python 3\.12\.' <<<"$v" && echo "$v"; }
health()      { local b; b="$(curl -fsS --max-time 5 "$OWUI_URL/health")" && grep -q '"status": *true' <<<"$b" && echo "$b"; }
local_only()  { local l; l="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sort -u)"
                [[ -n "$l" ]] && ! grep -Eqv "^(127\.0\.0\.1|\[::1\]):$1\$" <<<"$l" && echo $l; }
ollama_ver()  { local b; b="$(curl -fsS --max-time 5 "$OLLAMA_API/api/version")" && grep -q "\"$OLLAMA_VERSION\"" <<<"$b" && echo "$b"; }
login_known() { [[ -n "${OWUI_EMAIL:-}" && -n "${OWUI_PASSWORD:-}" ]]; }
signin()      { "${API_PY[@]}" "$OWUI_URL" "$TOKEN_FILE" signin "$OWUI_EMAIL" "$OWUI_PASSWORD"; }
api()         { "${API_PY[@]}" "$OWUI_URL" "$TOKEN_FILE" "$@"; }
db_in_data()  { [[ -s "$OWUI_DATA/webui.db" ]] && du -sh "$OWUI_DATA" | awk '{print "data/ " $1}'; }
no_autostart(){ local a s; a="$(ls "$HOME/Library/LaunchAgents" 2>/dev/null || true)"
                s="$(brew services list 2>/dev/null | awk 'NR>1 && $2!="none" {print $1}' || true)"
                ! grep -Eiq 'ollama|open-?webui' <<<"$a" && ! grep -Eiq 'ollama|open-?webui' <<<"$s"; }
disk_ok()     { local g; g="$(free_gb)"; (( g >= MIN_FREE_GB )) && echo "$g GB free"; }

check "open-webui is version $OWUI_VERSION"                    cli_ver
check "its venv runs Python 3.12"                              venv_py
check "Open WebUI answers on 127.0.0.1:8080/health"            health
check "Open WebUI listens on localhost only"                   local_only 8080
check "Ollama $OLLAMA_VERSION answers on 127.0.0.1:11434"      ollama_ver
check "Ollama listens on localhost only"                       local_only 11434
check "an admin login is known (env, admin-login.txt or .state)" login_known
check "sign-in works through the API (admin)"                  signin
check "new sign-ups are switched off"                          api signup-closed
check "the model picker lists the ${#MODELS[@]} local models, nothing else" api models "${MODELS[@]}"
check "gemma3:1b answers through Open WebUI (17 + 25 = 42)"   api chat gemma3:1b
check "llama3.2:3b answers through Open WebUI (17 + 25 = 42)" api chat llama3.2:3b
check "document Q&A: llama3.2:3b reads the licence (50 users)" api document llama3.2:3b "$HERE/demo/open-webui-LICENSE.txt"
check "the database is in ~/open-webui/data"                   db_in_data
check "nothing is set to start at login"                      no_autostart
check "at least $MIN_FREE_GB GB of disk still free"            disk_ok
for m in "${MODELS[@]}"; do ollama stop "$m" >/dev/null 2>&1 || true; done

echo "ALL CHECKS PASSED"
