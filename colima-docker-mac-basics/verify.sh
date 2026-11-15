#!/bin/bash
# Machine checks for Colima + Docker + the demo app. Prints ALL CHECKS PASSED or the first failing check.
# No accounts exist in this setup, so there is no login check; the real tasks are a container run and a page served
# from a named volume.
set -uo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
CPUS="${CPUS:-4}"; MEMORY="${MEMORY:-8}"; DISK="${DISK:-60}"
IMAGE="nginx:1.30.6-alpine"
URL="http://127.0.0.1:8080/"
MIN_FREE_GB=20
HERE="$(cd "$(dirname "$0")" && pwd)"
DC=(docker-compose -f "$HERE/compose.yaml")

n=0
check() { n=$((n + 1)); local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok $n  $name"; else echo "FAILED check $n: $name"; exit 1; fi; }

# Each check reads the whole output first, then tests it (a `cmd | grep -q` can fail under pipefail when grep
# stops reading early).
has()         { local out; out="$("${@:2}" 2>&1)" || return 1; grep -Eq -- "$1" <<<"$out"; }
versions_ok() { has "^colima version $PIN_COLIMA\$" colima version &&
                has "^Docker version $PIN_DOCKER," docker --version &&
                has "^$PIN_COMPOSE\$" docker-compose version --short; }
running_ok()  { colima status; }
size_ok()     { local j; j="$(colima list --json)" || return 1
                /usr/bin/python3 -c '
import json, sys
d = json.loads(sys.argv[4].splitlines()[0])
want = [int(x) for x in sys.argv[1:4]]
sys.exit(0 if [d["cpus"], d["memory"] // 2**30, d["disk"] // 2**30] == want and d["status"] == "Running" else 1)' \
                "$CPUS" "$MEMORY" "$DISK" "$j"; }
context_ok()  { [[ "$(docker context show)" == colima ]]; }
engine_ok()   { has '^[0-9]+\.' docker version --format '{{.Server.Version}}'; }
run_ok()      { [[ "$(docker run --rm "$IMAGE" echo container-ok)" == container-ok ]]; }
app_ok()      { has '^web$' "${DC[@]}" ps --status running --services; }
http_ok()     { has '[[:alnum:]]' curl -fsS --max-time 5 "$URL"; }   # 200 and a page (yours or nginx's)
local_only()  { local l; l="$(lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
                [[ -n "$l" ]] && ! grep -Eqv '^(127\.0\.0\.1|\[::1\]):8080$' <<<"$l"; }
logs_ok()     { has '"GET / HTTP' "${DC[@]}" logs --no-color web; }
volume_ok()   { has '^/var/lib/docker/volumes/colima-demo_html/_data$' docker volume inspect colima-demo_html --format '{{.Mountpoint}}'; }
disk_ok()     { (( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )); }
no_login()    { local s; s="$(brew services list 2>/dev/null || true)"
                ! awk '$1=="colima" {print $2}' <<<"$s" | grep -q started; }

check "colima $PIN_COLIMA, docker $PIN_DOCKER, docker-compose $PIN_COMPOSE"   versions_ok
check "colima is running"                                                     running_ok
check "VM has $CPUS CPUs, $MEMORY GiB memory, $DISK GiB disk"                 size_ok
check "docker uses the colima context"                                        context_ok
check "docker engine answers inside the VM"                                   engine_ok
check "a container runs and prints its output"                                run_ok
check "demo app container is running"                                         app_ok
check "demo app answers on $URL"                                              http_ok
check "demo app listens on localhost only"                                    local_only
check "docker-compose logs show the request"                                  logs_ok
check "app data is in a named volume inside the VM"                           volume_ok
check "colima is not set to start at login"                                   no_login
check "at least $MIN_FREE_GB GB of disk still free"                           disk_ok

echo "ALL CHECKS PASSED"
