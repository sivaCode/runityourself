> **Run It Yourself:** Local AI on your Mac with LM Studio: a 2.10 GB model, Wi-Fi off
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# LM Studio without the app: llmster and lms on a Mac (Run It Yourself, LM Studio course part 1)

Companion files for the Run It Yourself video (its link is added here once it is published).

LM Studio's headless engine (**llmster**) and its command-line tool (**lms**), installed with LM Studio's own
one-line installer, running a small local model (**IBM Granite 4.1 3B**) in the terminal. No desktop app, no
account, no login. Once the model is downloaded, it answers with Wi-Fi off.

- **Requirements:** a Mac with Apple Silicon (M1 to M4), macOS 14 or newer, 16 GB of memory recommended (8 GB works
  with small models like this one), and about 6 GB of disk (3.8 GB for llmster, 2.1 GB for the model). The scripts
  also keep 20 GB free and stop if there isn't room. Run the terminal natively, not under Rosetta.
- **Install:** `./install.sh` runs the official installer (`curl -fsSL https://lmstudio.ai/install.sh | bash`, after
  checking it still installs the tested llmster version), starts the engine with `lms daemon up` and downloads the
  model with `lms get ibm/granite-4.1-3b -y`. Then, in a new terminal (or after
  `export PATH="$HOME/.lmstudio/bin:$PATH"`):
  - `lms daemon status`: the engine is running
  - `lms ls`: the model is on disk
  - `lms chat ibm/granite-4.1-3b -p "your question"`: one answer, then back to the prompt (`lms chat` alone is
    an interactive chat; `/exit` leaves it)
- **Check:** `./verify.sh` (CPU and OS, the files, the PATH line, the engine, the model, a real answer, no network
  port open to other machines, no login, no login item).
- **Remove:** `./uninstall.sh` stops the engine and deletes `~/.lmstudio` (llmster, lms **and every model you
  downloaded**), `~/.lmstudio-home-pointer` and the two PATH lines the installer added to `~/.zshrc`. A profile that
  was there before is left exactly as it was; one the installer created is deleted.
- **What the install changes:** `~/.lmstudio/` (`bin/lms`, `llmster/0.1.1-2/`, `models/`, `.internal/`),
  `~/.lmstudio-home-pointer`, and two lines at the end of `~/.zshrc`:
  `# Added by LM Studio CLI tool (lms)` and an `export PATH=…/.lmstudio/bin` line with your home folder spelled out.
  No login item, LaunchAgent or background service: the engine runs until `lms daemon down`, a log-out or a restart.
- **Licence:**
  - **LM Studio / llmster (the engine): proprietary, closed source**, under LM Studio's terms
    (https://lmstudio.ai/app-terms, version 23 Aug 2026, read 18 Nov 2026). Free for personal and internal business
    use. Not allowed: offering it to others as a hosted service, reselling or redistributing it, modifying or
    reverse-engineering it.
  - **lms (the CLI): MIT** (https://github.com/lmstudio-ai/lms).
  - **The model** carries its own licence: Granite 4.1 3B is Apache 2.0 (its LM Studio catalogue page).
- **Backups:** nothing to back up but the models, and they can be downloaded again (`lms get`). Chats with `lms chat`
  aren't saved.
- **Updates:** `lms daemon down`, then `lms daemon update`, then `lms daemon up`. The scripts pin llmster 0.1.1-2:
  when the installer moves to a new version, `install.sh` stops and says so, so you can read the release notes first.
- **Safety:** this setup opens no network port to other machines. It never runs `lms server start`. If you start
  the API server later, keep it on this Mac (localhost) and don't bind it to `0.0.0.0`: its authentication is off
  by default.

Tested on: Mac mini M4 (Mac16,10), 16 GB, macOS 26.5.2; llmster 0.1.1-2, lms CLI commit 138dcff,
ibm/granite-4.1-3b (GGUF Q4_K_M), 19 Nov 2026.

## Files
- `install.sh`
- `lib/state.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
