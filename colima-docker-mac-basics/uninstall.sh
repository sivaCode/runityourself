#!/bin/bash
# Put the Mac back as it was found (.state/before.env saved by install.sh). It deletes the
# Colima VM with all its containers, images and volumes (the demo app's data too) and the downloaded VM image.
# Works from any state: installed or not, VM running, stopped or broken, tools present or not.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_INSTALL_CLEANUP=1
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }
problems=0
note() { echo "note: $*"; }
profiles() { command -v colima >/dev/null 2>&1 || return 0; local j; j="$(colima list --json 2>/dev/null || true)"
             grep -o '"name":"[^"]*"' <<<"$j" | cut -d'"' -f4 || true; }   # one profile name per line
bad()  { echo "PROBLEM: $*"; problems=$((problems + 1)); }

# Without a saved state, keep what might be yours (folders, caches, formulae) and remove only the VM.
WAS_colima=keep WAS_lima=keep WAS_docker=keep WAS_docker_compose=keep
COLIMA_DIR_EXISTED=keep DOCKER_DIR_EXISTED=keep DOCKER_CONFIG_EXISTED=keep SSH_CONFIG_EXISTED=keep
COLIMA_CACHE_EXISTED=yes LIMA_CACHE_EXISTED=yes
if [[ -f "$STATE" ]]; then source "$STATE"; else note "no saved state ($STATE): only the Colima VM is removed"; fi

# 1. The demo app and the VM (containers, images, volumes and the data disk: --data)
if command -v colima >/dev/null 2>&1; then
  if colima status >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
    limit 120 docker-compose -f "$HERE/compose.yaml" down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  if grep -qx default <<<"$(profiles)"; then
    limit 300 colima delete --data --force || { limit 120 colima stop --force || true; limit 300 colima delete --data --force || bad "colima delete failed"; }
  fi
fi
pgrep -f 'limactl hostagent.*colima' >/dev/null && { pkill -f 'limactl hostagent.*colima' || true; sleep 2; }
pgrep -f 'limactl hostagent.*colima' >/dev/null && bad "a Colima VM process is still running"

# 2. Docker CLI settings: the colima context and currentContext in ~/.docker/config.json
case "$DOCKER_DIR_EXISTED" in
  no)   rm -rf "$HOME/.docker" ;;
  yes)  if command -v docker >/dev/null 2>&1; then docker context rm -f colima >/dev/null 2>&1 || true; fi
        if [[ -f "$STATE_DIR/docker-config.json" ]]; then cp -p "$STATE_DIR/docker-config.json" "$HOME/.docker/config.json"
        elif [[ "$DOCKER_CONFIG_EXISTED" == no ]]; then rm -f "$HOME/.docker/config.json"; fi ;;
  *)    if command -v docker >/dev/null 2>&1; then
          [[ "$(docker context show 2>/dev/null)" == colima ]] && docker context use default >/dev/null 2>&1
          docker context rm -f colima >/dev/null 2>&1 || true
        fi ;;
esac

# 3. ~/.ssh/config: colima start puts "Include ~/.colima/ssh_config" and a blank line at the top (build, 15 Nov
#    2026). Take out only those two lines; everything else in the file stays as it is.
SSHC="$HOME/.ssh/config"
if [[ -f "$SSHC" ]] && grep -Eq '^Include .*\.colima/ssh_config$' "$SSHC"; then
  tmp="$(mktemp "$HOME/.ssh/.config.XXXXXX")"
  awk '/^Include .*\.colima\/ssh_config$/ {skip=1; next} skip && /^$/ {skip=0; next} {skip=0; print}' "$SSHC" > "$tmp" &&
    chmod 600 "$tmp" && mv "$tmp" "$SSHC" || { rm -f "$tmp"; bad "could not take colima's line out of ~/.ssh/config"; }
fi
if [[ "$SSH_CONFIG_EXISTED" == no && -f "$SSHC" && ! -s "$SSHC" ]]; then rm -f "$SSHC"; fi
if [[ -f "$STATE_DIR/ssh-config.sha256" && -f "$SSHC" ]]; then
  [[ "$(shasum -a 256 "$SSHC" | awk '{print $1}')" == "$(cat "$STATE_DIR/ssh-config.sha256")" ]] ||
    note "~/.ssh/config differs from how it was found (changed by something else meanwhile?)"
fi

# 4. ~/.colima (and the VM image Colima downloaded)
if [[ "$COLIMA_DIR_EXISTED" != keep ]]; then
  if [[ -n "$(profiles)" ]]; then
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

# 5. Formulae: back to the found set (removed if install.sh added them)
for f in colima docker docker-compose lima; do
  var="WAS_${f//-/_}"; was="${!var}"
  now="$(ver_of "$f")"
  if [[ "$was" == none && -n "$now" ]]; then
    [[ "$f" == lima && -n "$(brew uses --installed lima 2>/dev/null || true)" ]] && { note "lima kept: another formula needs it"; continue; }
    brew uninstall --formula "$f" || bad "brew uninstall $f failed"
  elif [[ "$was" != none && "$was" != keep && -z "$now" ]]; then
    [[ "$f" == lima ]] && continue                     # comes back with colima
    limit 900 brew install "$f" || bad "brew install $f failed"
  fi
done
if [[ "$WAS_lima" != none && "$WAS_lima" != keep && -z "$(ver_of lima)" ]]; then limit 600 brew install lima || bad "brew install lima failed"; fi
for f in colima docker docker-compose lima; do
  var="WAS_${f//-/_}"; was="${!var}"; now="$(ver_of "$f")"
  [[ "$was" == keep || "$was" == none || -z "$now" || "$now" == "$was" ]] || note "$f was $was before; now $now"
done

(( problems == 0 )) || { echo "uninstall finished with $problems problem(s); .state kept"; exit 1; }
rm -rf "$STATE_DIR"
echo "uninstalled (Colima VM, its data and image cache removed; formulae as found)"
