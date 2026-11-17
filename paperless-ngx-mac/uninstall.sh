#!/bin/bash
# Remove Paperless-ngx: the three containers, their images, the Docker volumes (your documents, the database and the
# search index), .env (the secrets), consume/ and export/ (your backups: copy export/ somewhere safe first). Then put
# the Mac back as it was found (.state/before.env, saved by install.sh): a Colima VM that install.sh created is
# deleted, one that was there already is left as it was.
# Works from any state: installed or not, VM running, stopped or missing, tools present or not.
#   ./uninstall.sh            asks before deleting your documents and backups (when run in a terminal)
#   ./uninstall.sh --yes      no questions
#   ./uninstall.sh --keep-data   remove the containers and images only; keep volumes, .env and export/
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
# compose needs the variables to read compose.yaml; their values don't matter for `down`
DC=(env DB_PASSWORD=unused SECRET_KEY=unused docker-compose --project-directory "$HERE" -f "$HERE/compose.yaml" --env-file /dev/null)
YES=no; KEEP_DATA=no
for a in "$@"; do case "$a" in --yes|-y) YES=yes ;; --keep-data) KEEP_DATA=yes ;; esac; done
problems=0
note() { echo "note: $*"; }
bad()  { echo "PROBLEM: $*"; problems=$((problems + 1)); }

# Without a saved state, keep what might be yours (the VM, folders, caches, formulae); remove only Paperless-ngx.
WAS_colima=keep WAS_lima=keep WAS_docker=keep WAS_docker_compose=keep WAS_VM=keep WAS_VM_SIZE=""
IMAGE_EXISTED_0=no IMAGE_EXISTED_1=no IMAGE_EXISTED_2=no VOLUMES_EXISTED=no ENV_EXISTED=no
COLIMA_DIR_EXISTED=keep DOCKER_DIR_EXISTED=keep DOCKER_CONFIG_EXISTED=keep SSH_CONFIG_EXISTED=keep
COLIMA_CACHE_EXISTED=yes LIMA_CACHE_EXISTED=yes
if [[ -f "$STATE" ]]; then source "$STATE"; else note "no saved state: only Paperless-ngx is removed"; fi

# 0. Your data: ask once (documents in the volumes, secrets in .env, backups in export/)
DEL_DATA=no
if [[ "$KEEP_DATA" != yes ]]; then
  if [[ "$YES" == yes ]]; then DEL_DATA=yes
  elif [[ -t 0 ]]; then
    read -r -p "Delete your Paperless documents, database, .env and the backups in export/? [y/N] " ans
    [[ "$ans" == [yY]* ]] && DEL_DATA=yes
  else
    DEL_DATA=yes     # no terminal (run from another script): the saved state decides what was ours
    [[ "$VOLUMES_EXISTED" == yes || "$ENV_EXISTED" == yes ]] && DEL_DATA=no
  fi
fi

# 1. The containers, volumes and images
if engine_up; then
  if [[ "$DEL_DATA" == yes ]]; then
    limit 180 "${DC[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || bad "docker-compose down failed"
  else
    limit 180 "${DC[@]}" down --remove-orphans >/dev/null 2>&1 || bad "docker-compose down failed"
  fi
  # anything left with the project's label (another folder's copy of this compose file, a half-made take)
  left="$(docker ps -aq --filter label=com.docker.compose.project=$PROJECT)"
  [[ -n "$left" ]] && { docker rm -f $left >/dev/null 2>&1 || bad "could not remove the paperless containers"; }
  if [[ "$DEL_DATA" == yes ]]; then
    for v in "${VOLUMES[@]}"; do docker volume rm "$v" >/dev/null 2>&1 || true; done
    left="$(docker volume ls -q --filter label=com.docker.compose.project=$PROJECT)"
    [[ -n "$left" ]] && { docker volume rm $left >/dev/null 2>&1 || bad "could not remove the paperless volumes"; }
  fi
  docker network rm paperless_default >/dev/null 2>&1 || true
  n=0
  for i in "${IMAGES[@]}"; do
    var="IMAGE_EXISTED_$n"; n=$((n + 1))
    if [[ "${!var}" != yes ]] && docker image inspect "$i" >/dev/null 2>&1; then
      docker image rm "$i" >/dev/null || bad "could not remove the image $i"
    fi
  done
  [[ -z "$(docker ps -aq --filter label=com.docker.compose.project=$PROJECT)" ]] || bad "paperless containers are still there"
elif [[ "$WAS_VM" != none && "$(vm_status)" == Stopped ]]; then
  note "Colima is stopped, so the containers, volumes and images inside it stay: run 'colima start', then ./uninstall.sh again"
fi

# 2. The files next to compose.yaml
if [[ "$DEL_DATA" == yes ]]; then
  # files the container wrote are owned by the VM's user; through Colima's mount they are still ours to delete
  rm -rf "$HERE/consume" "$HERE/export" || bad "could not delete consume/ or export/"
  rm -f "$HERE/.env" "$HERE/.env.tmp"
else
  note "your documents (in the Docker volumes), .env and export/ kept"
fi

# Kept data lives in the Colima VM's volumes: then the VM, the tools and .state stay too (a later
# `./uninstall.sh --yes` removes the rest and puts the Mac back as it was found).
if [[ "$DEL_DATA" != yes ]]; then
  (( problems == 0 )) || { echo "uninstall finished with $problems problem(s); .state kept"; exit 1; }
  echo "uninstalled the containers and images; your data, the Colima VM and Colima itself are kept"
  exit 0
fi

# 3. The Colima VM: delete it only if it wasn't there before; otherwise leave it as it was found
case "$WAS_VM" in
  none)
    if [[ "$(vm_status)" != none ]]; then
      limit 300 colima delete --data --force >/dev/null 2>&1 ||
        { limit 120 colima stop --force >/dev/null 2>&1 || true; limit 300 colima delete --data --force >/dev/null 2>&1 || bad "colima delete failed"; }
    fi
    pgrep -f 'limactl hostagent.*colima' >/dev/null && { pkill -f 'limactl hostagent.*colima' || true; sleep 2; }
    pgrep -f 'limactl hostagent.*colima' >/dev/null && bad "a Colima VM process is still running" ;;
  Stopped)
    [[ "$(vm_status)" == Running ]] && { limit 120 colima stop >/dev/null 2>&1 || bad "colima stop failed"; } ;;
  *) : ;;   # Running or unknown: left running
esac

# 4. Docker CLI settings (colima start adds a context and sets it as current)
if [[ "$WAS_VM" == none ]]; then
  case "$DOCKER_DIR_EXISTED" in
    no)  rm -rf "$HOME/.docker" ;;
    yes) if command -v docker >/dev/null 2>&1; then docker context rm -f colima >/dev/null 2>&1 || true; fi
         if [[ -f "$STATE_DIR/docker-config.json" ]]; then cp -p "$STATE_DIR/docker-config.json" "$HOME/.docker/config.json"
         elif [[ "$DOCKER_CONFIG_EXISTED" == no ]]; then rm -f "$HOME/.docker/config.json"; fi ;;
    *)   : ;;
  esac

  # ~/.ssh/config: colima start puts "Include ~/.colima/ssh_config" and a blank line at the top.
  SSHC="$HOME/.ssh/config"
  if [[ -f "$SSHC" ]] && grep -Eq '^Include .*\.colima/ssh_config$' "$SSHC"; then
    tmp="$(mktemp "$HOME/.ssh/.config.XXXXXX")"
    awk '/^Include .*\.colima\/ssh_config$/ {skip=1; next} skip && /^$/ {skip=0; next} {skip=0; print}' "$SSHC" > "$tmp" &&
      chmod 600 "$tmp" && mv "$tmp" "$SSHC" || { rm -f "$tmp"; bad "could not take colima's line out of ~/.ssh/config"; }
  fi
  if [[ "$SSH_CONFIG_EXISTED" == no && -f "$SSHC" && ! -s "$SSHC" ]]; then rm -f "$SSHC"; fi
  if [[ -f "$STATE_DIR/ssh-config.sha256" && -f "$SSHC" ]]; then
    [[ "$(shasum -a 256 "$SSHC" | awk '{print $1}')" == "$(cat "$STATE_DIR/ssh-config.sha256")" ]] ||
      note "~/.ssh/config differs from how it was found"
  fi

  # ~/.colima back to its found skeleton (only if no other profile is there), and the VM image caches
  if [[ "$COLIMA_DIR_EXISTED" != keep ]] && command -v colima >/dev/null 2>&1; then
    if [[ -n "$(colima list --json 2>/dev/null | grep -o '"name":"[^"]*"' || true)" ]]; then
      note "other Colima profiles exist; ~/.colima is kept"
    else
      rm -rf "$HOME/.colima"
      if [[ "$COLIMA_DIR_EXISTED" == yes ]]; then
        mkdir -p "$HOME/.colima"
        [[ -f "$STATE_DIR/colima-dirs.txt" ]] && while IFS= read -r d; do mkdir -p "$HOME/.colima/${d#./}"; done < "$STATE_DIR/colima-dirs.txt"
      fi
    fi
  fi
  [[ "$COLIMA_CACHE_EXISTED" == no ]] && rm -rf "$HOME/Library/Caches/colima"
  [[ "$LIMA_CACHE_EXISTED" == no ]] && rm -rf "$HOME/Library/Caches/lima"
fi

# 5. Formulae: back to the found set (removed if install.sh added them, reinstalled if they were there before)
for f in colima docker docker-compose lima; do
  var="WAS_${f//-/_}"; was="${!var}"; now="$(ver_of "$f")"
  if [[ "$was" == none && -n "$now" ]]; then
    [[ "$f" == lima && -n "$(brew uses --installed lima 2>/dev/null || true)" ]] && { note "lima kept: another formula needs it"; continue; }
    brew uninstall --formula "$f" >/dev/null || bad "brew uninstall $f failed"
  elif [[ "$was" != none && "$was" != keep && -z "$now" ]]; then
    [[ "$f" == lima ]] && continue                     # comes back with colima
    limit 900 brew install "$f" >/dev/null || bad "brew install $f failed"
  fi
done

(( problems == 0 )) || { echo "uninstall finished with $problems problem(s); .state kept"; exit 1; }
if [[ -f "$STATE" ]]; then rm -rf "$STATE_DIR"; echo "uninstalled (Paperless-ngx containers, images and data removed; the Mac is as it was found)"
else rm -rf "$STATE_DIR"; echo "uninstalled (Paperless-ngx removed; Colima and your other settings left as they are)"; fi
