> **Run It Yourself:** Replace Acrobat for OCR and redaction with Stirling-PDF on your Mac
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Stirling-PDF on your Mac: Run It Yourself

Companion files for the Run It Yourself video (its link is added here once it is published).

Stirling-PDF in one container on Colima (no Docker Desktop), used from your browser at http://localhost:8080 and
reachable from this Mac only. Merge, split, reorder, compress, OCR and redact PDFs without uploading them anywhere.

- **Requirements:** macOS 13 or newer on Apple silicon, Homebrew, about 10 GB of free disk (the image is 3.4 GB), and
  Colima with the Docker CLI and docker-compose (the Colima episode; `install.sh` installs them if they're missing).
  The Colima VM needs at least 6 GiB of memory: Stirling-PDF is capped at 4 GB.
- **Install:** `./install.sh` · **Check:** `./verify.sh` · **Remove:** `./uninstall.sh`
  - `install.sh` starts Colima (4 CPUs, 8 GiB, 60 GiB) if it isn't running, pulls the pinned image and starts it
    with `docker-compose up -d`, then waits until it's healthy.
  - `verify.sh` runs 18 checks: versions, localhost only, and real merge, reorder, compress, OCR and redaction jobs on
    the demo PDFs.
  - `uninstall.sh` removes the container, the image and `stirling-data/` (it asks first; `--keep-data` keeps it).
    A Colima VM that `install.sh` created is deleted; one you already had is left as it was.
- **Look inside a PDF:** `./pdf-check.sh file.pdf` (size, pages, text), `./pdf-check.sh --find "words" file.pdf`.
  It uses macOS's own PDF engine, so there's nothing to install.
- **Demo files:** `demo/in/` holds made-up documents (a fictional design studio): an invoice, a two-page agreement, a
  scanned letter and a six-page scan of 22 MB. None of them are real.
- **From the terminal:** the page in your browser sends each job to the server's API, and so can you. One request per
  job, the result saved in `demo/out/` under the server's file name (`mkdir -p demo/out` first):
  ```
  curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/scanned-report.pdf -F optimizeLevel=5 http://127.0.0.1:8080/api/v1/misc/compress-pdf
  curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/invoice.pdf -F fileInput=@demo/in/contract.pdf -F sortType=orderProvided http://127.0.0.1:8080/api/v1/general/merge-pdfs
  curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/scanned-letter.pdf -F languages=eng http://127.0.0.1:8080/api/v1/misc/ocr-pdf
  curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/invoice.pdf -F listOfText=0042-7781-3390 http://127.0.0.1:8080/api/v1/security/auto-redact
  ```
  The list of every endpoint is at http://localhost:8080/swagger-ui/index.html.
- **Keep this folder in your home folder:** Colima shares only that with its VM, so the `stirling-data/` folders reach
  your Mac. Elsewhere, start Colima with `--mount "$HOME:w" --mount "<this folder>:w"` (`install.sh` checks).
- **Settings:** in `compose.yaml`. Login is off (`SECURITY_ENABLELOGIN=false`) because the port is published on
  127.0.0.1 only: anyone who can reach the server can use it, and here that's only this Mac. If you publish it
  further, turn login on first. Analytics are off (`SYSTEM_ENABLEANALYTICS=false`).
- **Licence of Stirling-PDF:** open-core, read 16 Nov 2026. Most of the code is MIT. Eight folders, including the
  login and admin module in the official image, are under Stirling's own "Stirling PDF User License". The Free plan
  covers all PDF tools for up to 5 users. Going past 5 users, Team/Enterprise features, and client-facing or commercial
  use of the licensed parts need a paid plan. See https://github.com/Stirling-Tools/Stirling-PDF/blob/main/LICENSE and
  https://docs.stirlingpdf.com. This is a summary, not legal advice.
- **Backups and updates:**
  - Back up `stirling-data/configs` (settings, the built-in database, keys) before an update:
    `tar -czf configs-backup.tgz stirling-data/configs`.
  - Update: change the tag in `compose.yaml` to the new version, then `docker-compose pull && docker-compose up -d`.
    Your folders carry over.
  - Docker on a Mac with Colima: see the Colima episode in the same playlist.

Tested on: 16 Nov 2026, Mac mini (M4, 16 GB), macOS 26.5.2, Stirling-PDF 3.3.0, Colima 0.10.3 (Lima 2.3.0),
Docker CLI 29.9.3, docker-compose 5.7.1. Two clean install, verify and uninstall passes.

## Files
- `compose.yaml`
- `install.sh`
- `lib/state.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
