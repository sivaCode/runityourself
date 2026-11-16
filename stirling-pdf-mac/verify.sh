#!/bin/bash
# Stirling-PDF on a Mac: machine checks. Every check is a real request or a real file. Prints ALL CHECKS PASSED, or
# the first check that failed. Login is off in this setup (one user, this Mac only), so instead of a sign-in it
# checks that the API answers on this Mac and nowhere else; the real tasks run on the demo PDFs in demo/in/
# (results go to a temporary folder, so demo/out/ is left as it is).
set -uo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
VERSION="3.3.0"
B="http://127.0.0.1:8080"
MIN_FREE_GB=5
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$HERE/stirling-data"
IN="$HERE/demo/in"
TMP="$(mktemp -d /tmp/stirling-verify.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
DC=(docker-compose -f "$HERE/compose.yaml")

n=0
check() { n=$((n + 1)); local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok $n  $name"; else echo "FAILED check $n: $name"
    [[ -n "${VERBOSE:-}" ]] && { set -x; "$@"; }; exit 1; fi; }   # VERBOSE=1 ./verify.sh shows why
# Read the whole output first, then test it (`cmd | grep -q` can fail under pipefail when grep stops early).
has()  { local out; out="$("${@:2}" 2>&1)" || return 1; grep -Eq -- "$1" <<<"$out"; }
post() { local out="$1" path="$2"; shift 2
         [[ "$(curl -s -o "$TMP/$out" -w '%{http_code}' --max-time 120 "$@" "$B$path")" == 200 ]]; }
pdf()  { "$HERE/pdf-check.sh" "$@"; }
size() { stat -f %z "$1"; }

versions_ok() { has "^colima version $PIN_COLIMA\$" colima version &&
                has "^Docker version $PIN_DOCKER," docker --version &&
                has "^$PIN_COMPOSE\$" docker-compose version --short; }
colima_ok()   { has '"name":"default".*"status":"Running"' colima list --json; }
context_ok()  { [[ "$(docker context show)" == colima ]]; }
running_ok()  { [[ "$(docker inspect stirling-pdf --format '{{.State.Running}} {{.Config.Image}}')" == \
                   "true docker.stirlingpdf.com/stirlingtools/stirling-pdf:$VERSION" ]]; }
limit_ok()    { [[ "$(docker inspect stirling-pdf --format '{{.HostConfig.Memory}}')" == 4294967296 ]]; }
status_ok()   { has "\"version\":\"$VERSION\",\"status\":\"UP\"" curl -fsS --max-time 5 "$B/api/v1/info/status"; }
health_ok()   { [[ "$(docker inspect stirling-pdf --format '{{.State.Health.Status}}')" == healthy ]]; }
local_only()  { local l; l="$(lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
                [[ -n "$l" ]] && ! grep -Eqv '^(127\.0\.0\.1|\[::1\]):8080$' <<<"$l"; }
not_on_lan()  { local ip; for ip in $(ifconfig | awk '$1=="inet" && $2!~/^127\./ {print $2}'); do
                  curl -s -o /dev/null --max-time 3 "http://$ip:8080/api/v1/info/status" && return 1; done; return 0; }
no_account()  { local c; c="$(curl -s "$B/api/v1/config/app-config")" &&
                grep -q '"enableAnalytics":false' <<<"$c" && grep -q '"isAdmin":false' <<<"$c" &&
                # an API task works without signing in: login is off (compose.yaml, SECURITY_ENABLELOGIN=false)
                post probe.pdf /api/v1/misc/compress-pdf -F fileInput=@"$IN/invoice.pdf" -F optimizeLevel=1; }
merge_ok()    { post merged.pdf /api/v1/general/merge-pdfs -F fileInput=@"$IN/invoice.pdf" \
                  -F fileInput=@"$IN/contract.pdf" -F sortType=orderProvided &&
                has ', 3 pages,' pdf "$TMP/merged.pdf"; }
reorder_ok()  { post reversed.pdf /api/v1/general/rearrange-pages -F fileInput=@"$TMP/merged.pdf" -F customMode=REVERSE_ORDER &&
                has '^AGREEMENT \(page 2 of 2\)' pdf --text "$TMP/reversed.pdf"; }
compress_ok() { post small.pdf /api/v1/misc/compress-pdf -F fileInput=@"$IN/scanned-report.pdf" -F optimizeLevel=5 &&
                has ', 6 pages,' pdf "$TMP/small.pdf" &&
                (( $(size "$TMP/small.pdf") * 4 < $(size "$IN/scanned-report.pdf") )); }   # under a quarter
ocr_ok()      { has 'no text' pdf "$IN/scanned-letter.pdf" &&
                post ocr.pdf /api/v1/misc/ocr-pdf -F fileInput=@"$IN/scanned-letter.pdf" -F languages=eng &&
                has 'found 1 time$' pdf --find "proofs are ready" "$TMP/ocr.pdf"; }
redact_ok()   { has 'found 1 time$' pdf --find "0042-7781-3390" "$IN/invoice.pdf" &&
                post redacted.pdf /api/v1/security/auto-redact -F fileInput=@"$IN/invoice.pdf" -F listOfText=0042-7781-3390 &&
                has 'found 0 times$' pdf --find "0042-7781-3390" "$TMP/redacted.pdf" &&
                has 'found 0 times$' pdf --find "00427781" "$TMP/redacted.pdf" &&
                has 'found 1 time$' pdf --find "Invoice no. 2026-117" "$TMP/redacted.pdf"; }
data_ok()     { [[ -s "$DATA/configs/settings.yml" ]] && ls "$DATA"/configs/stirling-pdf-DB-*.mv.db >/dev/null &&
                [[ -d "$DATA/tessdata" && -d "$DATA/storage" ]]; }
no_login()    { local s; s="$(brew services list 2>/dev/null || true)"
                ! awk '$1=="colima" {print $2}' <<<"$s" | grep -q started &&
                ! ls "$HOME"/Library/LaunchAgents/*colima* >/dev/null 2>&1; }
disk_ok()     { (( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )); }

check "colima $PIN_COLIMA, docker $PIN_DOCKER, docker-compose $PIN_COMPOSE"  versions_ok
check "colima is running"                                                    colima_ok
check "docker uses the colima context"                                       context_ok
check "the stirling-pdf container runs image $VERSION"                       running_ok
check "the container is capped at 4 GB of memory"                            limit_ok
check "Stirling-PDF $VERSION reports UP"                                     status_ok
check "the container's health check says healthy"                            health_ok
check "port 8080 listens on localhost only"                                  local_only
check "not reachable from this Mac's network addresses"                      not_on_lan
check "no sign-in needed, analytics off"                                     no_account
check "merge: invoice + contract = 3 pages"                                  merge_ok
check "reorder: reversed, the last page comes first"                         reorder_ok
check "compress: the 6-page scan shrinks to under a quarter"                 compress_ok
check "OCR: the scanned letter becomes searchable text"                      ocr_ok
check "redact: the account number is gone from the text"                     redact_ok
check "settings and database are in stirling-data on this Mac"               data_ok
check "nothing set to start at login"                                        no_login
check "at least $MIN_FREE_GB GB of disk still free"                          disk_ok

echo "ALL CHECKS PASSED"
