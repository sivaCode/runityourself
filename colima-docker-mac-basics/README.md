> **Run It Yourself:** Replace Docker Desktop with Colima on your Mac: $0 vs $24/mo
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Colima: Docker on your Mac without Docker Desktop (Run It Yourself)

Companion files for the Run It Yourself video (its link is added here once it is published).

Colima runs a small Linux VM on your Mac with the Docker engine inside it. The normal `docker` and `docker-compose`
commands on your Mac talk to that VM. This folder installs Colima, the Docker CLI and docker-compose with Homebrew,
starts a VM sized for a 16 GB Mac, and runs a small demo web app from `compose.yaml` so you can check that everything works.

## Requirements
- A Mac with macOS 13 or newer (tested on an Apple M4 Mac mini, 16 GB, macOS 26.5.2)
- [Homebrew](https://brew.sh)
- About 25 GB of free disk (the VM disk grows as you use it, up to the size you set)
- Nothing else listening on port 8080 (the demo app)

## Steps
| | Command | What it does |
|---|---|---|
| Install | `./install.sh` | `brew install colima docker docker-compose`, then `colima start --cpus 4 --memory 8 --disk 60`, then `docker-compose up -d` for the demo app |
| Check | `./verify.sh` | 13 checks: versions, VM size, Docker context, a container run, the app on `http://127.0.0.1:8080/`, localhost only, logs, the named volume, no login item. Ends with `ALL CHECKS PASSED` |
| Remove | `./uninstall.sh` | Deletes the Colima VM with all its containers, images and volumes, and the downloaded VM image. Puts back what was there before (it reads `.state/`, which `install.sh` saves the first time it runs) |

By hand, the same thing:
```sh
brew install colima docker docker-compose
colima start --cpus 4 --memory 8 --disk 60     # memory and disk in GiB
docker context ls                              # colima is the active context (*)
docker-compose up -d                           # in this folder
open http://127.0.0.1:8080/
docker-compose logs web
docker system df
docker-compose down                            # add --volumes to delete the app's data too
colima stop
```

## Good to know
- **Sizing:** CPU and memory change only with `colima stop`, then `colima start --cpus … --memory …`. You can grow the disk
  later but never shrink it. Colima's defaults are 2 CPUs, 2 GiB of memory and a 100 GiB disk.
- **Where the data lives:** inside the VM, not in this folder. A named volume sits at `/var/lib/docker/volumes/…`
  in the VM, and the VM's disks are under `~/.colima/`. `colima delete` keeps container data. `colima delete --data`
  removes it.
- **After a reboot** Colima doesn't start on its own. Run `colima start`. (`brew services start colima` would make it
  start at login. This guide doesn't use that.)
- **Safe defaults:** the demo app is published on `127.0.0.1` only, so other machines on your network can't reach it.
  Don't use `colima start --network-address` or link `/var/run/docker.sock` with `sudo` unless you know why you need it.
- **`docker compose` (with a space):** Homebrew's docker-compose also works as a Docker plugin if you add
  `"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]` to `~/.docker/config.json`. This guide uses
  `docker-compose` and leaves that file alone.
- **Apps that ignore Docker contexts** (they look for `/var/run/docker.sock`): set
  `DOCKER_HOST=unix://$HOME/.colima/default/docker.sock` for them.

## Licences (read 15 Nov 2026)
- **Colima:** MIT ([LICENSE](https://github.com/abiosoft/colima/blob/main/LICENSE)). Any business may use, change
  and redistribute it at no cost if it keeps the copyright notice. No warranty.
- **Docker CLI, docker-compose, Lima:** Apache License 2.0 ([cli](https://github.com/docker/cli/blob/master/LICENSE),
  [compose](https://github.com/docker/compose/blob/main/LICENSE), [lima](https://github.com/lima-vm/lima/blob/master/LICENSE)).
- **Docker Desktop** isn't open source. It's licensed under the Docker Subscription Service Agreement, and it's free only
  for companies under both 250 employees and US $10 million a year in revenue (and for personal use, education and
  non-commercial open source). Nothing here installs it.
- The demo image `nginx:1.30.6-alpine` is nginx (BSD-2-Clause) on Alpine Linux.

## Backups and updates
- Back up an app's data before `docker-compose down --volumes`, `colima delete --data` or `./uninstall.sh`. All
  three delete it. The app episodes in this playlist show a backup and a restore test for each app.
- To update: `brew upgrade colima docker docker-compose`. After a Colima upgrade, Colima's FAQ recommends
  `colima delete` and a fresh `colima start`, so back up first.

Tested on: Colima 0.10.3 (Lima 2.3.0), Docker CLI 29.9.3, docker-compose 5.7.1, on 15 Nov 2026.

## Files
- `compose.yaml`
- `install.sh`
- `lib/state.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
