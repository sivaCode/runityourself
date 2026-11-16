> **Run It Yourself:** Replace ChatGPT Plus with Open WebUI and Ollama on your Mac
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Open WebUI + Ollama: a private ChatGPT-style chat on your Mac (Run It Yourself)

Companion files for the Run It Yourself video (its link is added here once it is published).

Open WebUI is a self-hosted chat app that runs in your browser and talks to the Ollama models on your own Mac. It
gives you chat history, a model picker and questions about your own documents, with no cloud account. This folder
installs it the Docker-free way: Homebrew's Python 3.12, a virtual environment, and a pinned `pip install
open-webui`. It sits next to a native Ollama (Homebrew formula, Metal GPU) with three small models.

## Requirements
- An Apple silicon Mac with macOS 14 (Sonoma) or newer (tested on an Apple M4 Mac mini, 16 GB, macOS 26.5.2)
- [Homebrew](https://brew.sh)
- About 32 GB of free disk before you start: about 5 GB of models, about 3 GB for Open WebUI and its Python
  packages, and 20 GB left free afterwards
- Nothing else on port 8080 (Open WebUI) or 11434 (Ollama)
- Python **3.11 or 3.12**. Open WebUI doesn't install on Python 3.13 or newer, so this guide uses `python@3.12`

## Steps
| | Command | What it does |
|---|---|---|
| Install | `./install.sh` | Installs Ollama 0.40.16 if it's missing and pulls `gemma3:1b`, `llama3.2:3b` and `qwen3.5:2b-q4_K_M`. Installs `python@3.12`, creates `~/open-webui/venv`, runs `pip install open-webui==0.13.3`, then starts both servers on `127.0.0.1`. It creates a throwaway admin, `demo@example.com`, and saves its login in `~/open-webui/admin-login.txt` (only you can read it). Run with `CREATE_ADMIN=0` to make your own admin in the browser instead |
| Check | `./verify.sh` | 16 checks: versions, both servers on localhost only, sign-in through the API, new sign-ups switched off, the model list, a real chat with two models, a question about a document, the database in `~/open-webui/data`, nothing set to start at login, free disk. Ends with `ALL CHECKS PASSED` |
| Remove | `./uninstall.sh` | Stops both servers and deletes `~/open-webui` **with your chats and uploads**. It removes the models, formulae and caches that weren't on the Mac before (it reads `.state/`, which `install.sh` saves the first time it runs) |

By hand, the same thing (Ollama already running, as in the previous episode):
```sh
brew install python@3.12
python3.12 -m venv ~/open-webui/venv
source ~/open-webui/venv/bin/activate
pip install open-webui==0.13.3
open-webui --version
(cd ~/open-webui && DATA_DIR=~/open-webui/data ENABLE_OPENAI_API=false \
  nohup open-webui serve --host 127.0.0.1 --port 8080 > serve.log 2>&1 &)   # keeps running if you close the window
until curl -s http://127.0.0.1:8080/health; do sleep 2; done   # {"status":true}
open http://localhost:8080                                       # the first account you create is the admin
```

## Good to know
- **Localhost only:** `open-webui serve` listens on `0.0.0.0`, which is every network interface, unless you pass
  `--host 127.0.0.1`. Don't open port 8080 to your network without private access (a VPN such as Tailscale or
  WireGuard) in front of it.
- **Where the data lives:** `DATA_DIR=~/open-webui/data` holds the database (`webui.db`), uploads, the vector store
  and the document-embedding model. Without `DATA_DIR`, a pip install keeps its data inside the venv's
  `site-packages`, where `pip uninstall` leaves it behind.
- **Start it from `~/open-webui`:** without `WEBUI_SECRET_KEY` set, Open WebUI writes `.webui_secret_key` into the
  folder you start it from. Starting from the same folder every time keeps you signed in across restarts.
- **Sign-ups:** the first account becomes the admin, and new sign-ups switch off by themselves after it's created
  (`./verify.sh` checks this). The switch is in the Admin Panel's settings if you ever want to invite someone.
- **No OpenAI connection:** `ENABLE_OPENAI_API=false` removes the default OpenAI connection, so the model picker shows
  only your local models. Once a setting is saved in the Admin Panel, the saved value wins over the environment variable.
- **Documents:** the first start downloads the embedding model `sentence-transformers/all-MiniLM-L6-v2` from Hugging
  Face into `~/.cache/huggingface` (not into `data/`; about 0.9 GB in our test). Start Open WebUI once while you're
  online. After that, chats and document questions work with
  Wi-Fi off. Ollama's default context on a 16 GB Mac is 4096 tokens, so keep documents short (about a page).
- **After a reboot** nothing starts on its own: run `ollama serve &` (or open the Ollama app), then the
  `open-webui serve` line above. This guide never uses `brew services` or login items.
- **Stop it:** `pkill -f "open-webui serve"`.

## Licences (read 15 Nov 2026)
- **Open WebUI:** the Open WebUI License, a custom licence. It's BSD-3-Clause terms plus a branding clause, and the
  project itself says it isn't an OSI-approved open-source licence. A business may use, change and run it for staff
  or clients at no cost **as long as the Open WebUI name and logo stay**. Removing or replacing the branding is allowed
  only for deployments with up to 50 end users in any rolling 30 days, or with written permission or an enterprise
  licence. No warranty. ([LICENSE](https://github.com/open-webui/open-webui/blob/main/LICENSE))
- **Ollama:** MIT ([LICENSE](https://github.com/ollama/ollama/blob/main/LICENSE)).
- **The models keep their own licences:** Gemma Terms of Use (`gemma3:1b`), Llama 3.2 Community License
  (`llama3.2:3b`), Apache-2.0 (`qwen3.5:2b`).
- `demo/open-webui-LICENSE.txt` is Open WebUI's own LICENSE file, used as the demo document.

## Backups and updates
- **Back up before every update:** database migrations are one-way. Stop the server, then copy the data folder:
  ```sh
  pkill -f "open-webui serve"
  cp -R ~/open-webui/data ~/open-webui/data-backup-$(date +%Y%m%d)
  source ~/open-webui/venv/bin/activate
  pip install --upgrade open-webui==<new version>
  ```
  Then start it again with the `open-webui serve` line above and hard-refresh the browser (Cmd+Shift+R).
  To roll back, stop it, put the backup folder back as `data`, and `pip install open-webui==<old version>`.
- To update Ollama: `brew upgrade ollama`.

Tested on: Open WebUI 0.13.3 (pip, Python 3.12.16), Ollama 0.40.16, on an Apple M4 Mac mini (16 GB, macOS 26.5.2),
15 Nov 2026. `./install.sh` took 4.5–4.9 minutes from nothing (models included), and `./verify.sh` about 10 seconds.

## Files
- `install.sh`
- `lib/common.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
