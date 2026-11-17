#!/bin/bash
# Paperless-ngx on a Mac: machine checks. Every check is a real request, a real file or a real container. Prints
# ALL CHECKS PASSED, or the first check that failed. The real task: a made-up café receipt (demo/verify/, an image
# with no text) goes into consume/, Paperless OCRs it, the search finds a word printed on it, and then the check
# deletes it again (trash emptied), so your documents are left as they were. The backup check exports to a folder
# inside the container and removes it, so export/ is left as it is too.
set -uo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
VERSION="3.5.0"
B="http://127.0.0.1:8000"
MIN_FREE_GB=5
HERE="$(cd "$(dirname "$0")" && pwd)"
DC=(docker-compose --project-directory "$HERE" -f "$HERE/compose.yaml")
TMP="$(mktemp -d /tmp/paperless-verify.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
ADMIN_USER="$(sed -n 's/^ADMIN_USER=//p' "$HERE/.env" 2>/dev/null)"
ADMIN_PASSWORD="$(sed -n 's/^ADMIN_PASSWORD=//p' "$HERE/.env" 2>/dev/null)"
printf 'user = "%s:%s"\n' "$ADMIN_USER" "$ADMIN_PASSWORD" > "$TMP/auth"; chmod 600 "$TMP/auth"
printf 'user = "%s:wrong-%s"\n' "$ADMIN_USER" "$RANDOM" > "$TMP/bad"

n=0
check() { n=$((n + 1)); local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok $n  $name"; else echo "FAILED check $n: $name"
    [[ -n "${VERBOSE:-}" ]] && { set -x; "$@"; }; exit 1; fi; }   # VERBOSE=1 ./verify.sh shows why
# Read the whole output first, then test it (`cmd | grep -q` can fail under pipefail when grep stops early).
has()  { local out; out="$("${@:2}" 2>&1)" || return 1; grep -Eq -- "$1" <<<"$out"; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }
api()  { curl -fsS --max-time 30 -K "$TMP/auth" -H 'Accept: application/json; version=10' "$@"; }
js()   { /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
cid()  { "${DC[@]}" ps -q "$1"; }

versions_ok() { has "^colima version $PIN_COLIMA\$" colima version &&
                has "^Docker version $PIN_DOCKER," docker --version &&
                has "^$PIN_COMPOSE\$" docker-compose version --short; }
colima_ok()   { has '"name":"default".*"status":"Running"' colima list --json; }
context_ok()  { [[ "$(docker context show)" == colima ]]; }
images_ok()   { [[ "$(docker inspect "$(cid webserver)" --format '{{.State.Running}} {{.Config.Image}}')" == "true ghcr.io/paperless-ngx/paperless-ngx:$VERSION" ]] &&
                [[ "$(docker inspect "$(cid db)" --format '{{.State.Running}} {{.Config.Image}}')" == "true docker.io/library/postgres:18" ]] &&
                [[ "$(docker inspect "$(cid broker)" --format '{{.State.Running}} {{.Config.Image}}')" == "true docker.io/valkey/valkey:9-alpine" ]]; }
health_ok()   { [[ "$(docker inspect "$(cid webserver)" --format '{{.State.Health.Status}}')" == healthy ]]; }
local_only()  { local l; l="$(lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
                [[ -n "$l" ]] && ! grep -Eqv '^(127\.0\.0\.1|\[::1\]):8000$' <<<"$l"; }
not_on_lan()  { local ip; for ip in $(ifconfig | awk '$1=="inet" && $2!~/^127\./ {print $2}'); do
                  curl -s -o /dev/null --max-time 3 "http://$ip:8000/" && return 1; done; return 0; }
db_closed()   { [[ -z "$(docker inspect "$(cid db)" --format '{{json .NetworkSettings.Ports}}' | grep -o HostPort)" ]] &&
                [[ -z "$(docker inspect "$(cid broker)" --format '{{json .NetworkSettings.Ports}}' | grep -o HostPort)" ]]; }
login_needed(){ [[ "$(code "$B/api/documents/")" == 401 ]] && [[ "$(code -K "$TMP/bad" "$B/api/documents/")" == 401 ]]; }
login_ok()    { [[ -n "$ADMIN_USER" ]] && has "\"username\": ?\"$ADMIN_USER\"" api "$B/api/ui_settings/" &&
                has '"token": ?"[0-9a-f]{40}"' curl -fsS --max-time 10 -d "username=$ADMIN_USER" \
                  --data-urlencode "password=$ADMIN_PASSWORD" "$B/api/token/"; }
status_ok()   { local s; s="$(api "$B/api/status/")" &&
                [[ "$(js 'd["pngx_version"], d["database"]["type"], d["database"]["status"], d["tasks"]["redis_status"], d["tasks"]["celery_status"], d["tasks"]["index_status"]' <<<"$s")" == \
                   "$VERSION postgresql OK OK OK OK" ]]; }
secrets_ok()  { [[ -f "$HERE/.env" && "$(stat -f %Lp "$HERE/.env")" == 600 ]] &&
                ! grep -Eq '^(SECRET_KEY=change-me|DB_PASSWORD=paperless)$' "$HERE/.env" &&
                (( $(sed -n 's/^SECRET_KEY=//p' "$HERE/.env" | wc -c) > 40 )) &&
                (( ${#ADMIN_PASSWORD} >= 20 )); }
# The real task: consume folder → OCR → search → delete
# Paperless 3.5.0 can miss a file that lands while its folder watcher restarts (issue #13011; build gate run 1); its
# own full rescan finds it within 5 minutes. After 60 s the check touches the file once (as ./paper.sh wait does),
# then waits up to 330 s in all, and says so if it had to.
DOC="" NUDGED=""
consume_ok()  { local name="verify-receipt-$(date +%s).pdf" t
                cp "$HERE/demo/verify/verify-receipt.pdf" "$HERE/consume/$name" || return 1
                for t in $(seq 1 165); do
                  DOC="$(api "$B/api/documents/?original_filename__icontains=${name%.pdf}&fields=id" | js 'd["results"][0]["id"] if d["count"] else ""')"
                  [[ -n "$DOC" && ! -e "$HERE/consume/$name" ]] && return 0
                  (( t == 30 )) && [[ -e "$HERE/consume/$name" ]] && { touch "$HERE/consume/$name"; NUDGED=yes; }
                  sleep 2
                done; return 1; }
ocr_ok()      { has 'Cardamom' api "$B/api/documents/$DOC/?fields=content"; }
search_ok()   { [[ "$(api "$B/api/documents/?query=cardamom&fields=id" | js '" ".join(str(r["id"]) for r in d["results"])')" =~ (^| )$DOC( |$) ]]; }
delete_ok()   { [[ "$(code -K "$TMP/auth" -X DELETE "$B/api/documents/$DOC/")" == 204 ]] &&
                api -X POST -H 'Content-Type: application/json' -d "{\"documents\":[$DOC],\"action\":\"empty\"}" "$B/api/trash/" &&
                [[ "$(code -K "$TMP/auth" "$B/api/documents/$DOC/")" == 404 ]]; }
export_ok()   { local d="/tmp/verify-export-$$" x=("${DC[@]}" exec -T --user paperless webserver)
                "${x[@]}" mkdir -p "$d" &&
                "${x[@]}" document_exporter "$d" --no-progress-bar &&
                "${x[@]}" test -s "$d/manifest.json"; local rc=$?
                "${x[@]}" rm -rf "$d"; return $rc; }
folders_ok()  { [[ -d "$HERE/consume" && -d "$HERE/export" ]] &&
                limit_ssh test -d "$HERE/consume" && limit_ssh test -d "$HERE/export"; }
limit_ssh()   { perl -e 'alarm 60; exec @ARGV' -- colima ssh -- "$@"; }
volumes_ok()  { local v; for v in data media pgdata redisdata; do
                  docker volume inspect "paperless_$v" >/dev/null 2>&1 || return 1; done; }
no_login()    { local s; s="$(brew services list 2>/dev/null || true)"
                ! awk '$1=="colima" {print $2}' <<<"$s" | grep -q started &&
                ! ls "$HOME"/Library/LaunchAgents/*colima* >/dev/null 2>&1; }
disk_ok()     { (( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )); }

check "colima $PIN_COLIMA, docker $PIN_DOCKER, docker-compose $PIN_COMPOSE"   versions_ok
check "colima is running"                                                     colima_ok
check "docker uses the colima context"                                        context_ok
check "webserver $VERSION, postgres 18 and valkey 9 are running"              images_ok
check "the web app's health check says healthy"                               health_ok
check "port 8000 listens on localhost only"                                   local_only
check "not reachable from this Mac's network addresses"                       not_on_lan
check "the database and the broker have no port on the Mac"                   db_closed
check "the API refuses no password and a wrong password"                      login_needed
check "the admin signs in through the API and gets a token"                   login_ok
check "Paperless $VERSION reports PostgreSQL, Redis, tasks and index OK"      status_ok
check "secrets are generated and .env is readable by you only"                secrets_ok
check "a scan dropped in consume/ becomes a document"                         consume_ok
[[ -n "$NUDGED" ]] && echo "   note: the watcher missed the scan until it was touched (Paperless issue #13011)"
check "OCR: the scan's printed text is in the document"                       ocr_ok
check "search: one word printed on the scan finds it"                         search_ok
check "the test document is deleted again (trash emptied)"                    delete_ok
check "the document exporter writes a full backup"                            export_ok
check "consume/ and export/ are shared between the Mac and the VM"            folders_ok
check "documents, database and index are in Docker volumes"                   volumes_ok
check "nothing set to start at login"                                         no_login
check "at least $MIN_FREE_GB GB of disk still free"                           disk_ok

echo "ALL CHECKS PASSED"
