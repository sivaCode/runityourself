> **Run It Yourself:** Replace Evernote for scanned paperwork with Paperless-ngx on your Mac
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Paperless-ngx on your Mac: Run It Yourself

Companion files for the Run It Yourself video (its link is added here once it is published).

Paperless-ngx turns scans of receipts, invoices and letters into a searchable archive: it reads the text in each scan
(OCR), lets you find any document by a word printed on it, and can tag and file new documents by rules you set. This
folder runs it on your Mac with Colima (no Docker Desktop), from this Mac only, at http://localhost:8000.

## What you need
- An Apple silicon Mac with macOS 13 or newer, [Homebrew](https://brew.sh), and at least 8 GB of free disk (the
  images are about 4.2 GB on disk inside the Colima VM).
- Colima, the Docker CLI and docker-compose (`brew install colima docker docker-compose`; `install.sh` installs any
  that are missing). Tested with colima 0.10.3, docker 29.9.3 and docker-compose 5.7.1. Other versions: run
  `PIN_COLIMA=… PIN_DOCKER=… PIN_COMPOSE=… ./install.sh` to accept them.
- Keep this folder in your home folder: Colima shares only that with its VM, and `consume/` and `export/` must reach
  the VM.

## Steps
```
./install.sh                     # Colima VM (4 CPUs, 8 GiB) if not running, .env with new secrets, 3 containers, admin user
./pdf-check.sh demo/scans/*.pdf  # four made-up scans: images only, no text yet
cp demo/scans/*.pdf consume/     # drop them in the consume folder
./paper.sh wait 4                # Paperless finds them (it looks every 5 s), reads the text and files them
./paper.sh list
./paper.sh find dehumidifier     # one word printed on the hardware-store receipt
./paper.sh rule tag Invoices any invoice
./paper.sh rule correspondent "Maple Lane Design Studio" exact "Maple Lane"
cp demo/new/maple-lane-invoice-118.pdf consume/ && ./paper.sh wait 5
./paper.sh list                  # the new invoice is tagged and filed by the rules
./verify.sh                      # 21 checks; prints ALL CHECKS PASSED
```
The web app is at http://localhost:8000: sign in as `paperless-admin`. Its password is in `.env` (open it in a text
editor; don't share it). `./paper.sh` uses the same REST API as the web app, with the same sign-in.

Every name, address and number in `demo/` is made up. Use your own scans once you're happy with it.

## What install.sh sets up, and why
- **`compose.yaml`**: the official `docker-compose.postgres.yml` (v3.5.0) with pinned images (Paperless-ngx 3.5.0,
  PostgreSQL 18, Valkey 9), the port on `127.0.0.1` only (nothing else on your network can reach it), the secrets
  from `.env` instead of the template's `change-me` / `paperless`, and the consume folder polled every 5 s (Colima's
  shared folders don't pass file events into the VM: a scan copied on the Mac is never seen otherwise).
- **`.env`**: a new secret key, database password and admin password, readable by you only (`chmod 600`).
- **Your documents, the database and the search index** live in Docker volumes inside the Colima VM
  (`paperless_media`, `paperless_pgdata`, `paperless_data`); `consume/` and `export/` are folders next to this file.
- Nothing starts at login. After a restart of the Mac, run `colima start`; the containers are set to
  `restart: unless-stopped`, so Docker starts them again.

## Back up and restore
```
docker-compose exec -T webserver document_exporter ../export --no-progress-bar   # everything, into ./export
```
Copy `export/` (and `.env`) to another disk. To restore into an empty install:
```
docker-compose down -v          # careful: deletes the documents, database and index in the volumes
docker-compose up -d && ./paper.sh up
docker-compose exec -T webserver document_importer ../export --no-progress-bar
```
The importer needs an empty install and the **same Paperless version** as the export. API tokens aren't in the
export (make new ones in the web app).

## Update
Make a backup first and wait until nothing is processing. Then change the image tag in `compose.yaml` (for example
`3.5.0` → the new release from https://github.com/paperless-ngx/paperless-ngx/releases) and run:
```
docker-compose pull && docker-compose up -d
```
Starting the new version applies its database changes. With the tag unchanged, `pull` changes nothing.

## Troubleshooting
- **A scan sits in `consume/` and nothing happens:** Paperless 3.5.0 restarts its folder watcher after every batch,
  and a file that lands in that moment waits for its full rescan (every 5 minutes; upstream issue #13011).
  `./paper.sh wait` touches such a file after 20 s, which wakes the watcher; by hand: `touch consume/<file>`.
- **`./verify.sh` fails:** `VERBOSE=1 ./verify.sh` shows why; `docker-compose logs webserver` shows Paperless's side.

## Remove
`./uninstall.sh` removes the containers, images, volumes, `.env`, `consume/` and `export/` (it asks first), and puts
the Mac back as `install.sh` found it (a Colima VM that install.sh started is deleted; one that was already there is
left alone). `./uninstall.sh --keep-data` removes only the containers and images, and keeps your documents, `.env`,
`export/` and the Colima VM that holds them; `./install.sh` brings it all back.

## Licence
Paperless-ngx is licensed under the GNU GPL v3 (licence file read 17 Nov 2026). A business may run it for its own
documents, with any number of users and no fee, and change it for internal use. Handing out copies, changed or not,
means giving the source under GPL-3.0 too. No warranty. https://github.com/paperless-ngx/paperless-ngx/blob/dev/LICENSE

Paperless-ngx keeps your documents unencrypted on disk: run it only on a machine you trust, and keep backups.

Tested on: Mac mini M4 (16 GB), macOS 26.5.2, Colima 0.10.3 (4 CPUs, 8 GiB, 60 GiB), docker 29.9.3,
docker-compose 5.7.1, Paperless-ngx 3.5.0, PostgreSQL 18.7, Valkey 9.1.3, 17 Nov 2026.

## Files
- `compose.yaml`
- `install.sh`
- `lib/state.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
