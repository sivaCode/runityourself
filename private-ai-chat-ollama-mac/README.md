> **Run It Yourself:** Run a private AI chatbot on your Mac with Ollama: real speed numbers
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Private AI chat on your Mac with Ollama

Ollama runs open-weight language models on your own Mac. Your prompts and answers stay on the machine: the server
listens on `127.0.0.1:11434` only, and no account is needed. This setup installs the Homebrew formula and three small
models, and checks that a chat works.

**Status: verified.** Two clean passes on 12 Nov 2026 with Ollama 0.40.16 and Homebrew 7.0.13. Both printed
`ALL CHECKS PASSED`, and install plus verify took about 2.2 minutes per pass.

## Requirements
- An Apple silicon Mac (M1 or newer) on macOS 14 Sonoma or newer
- Homebrew (https://brew.sh)
- About 5 GB of disk for the models (4.77 GB measured), plus the 20 GB this guide insists stays free
- Built on a Mac mini with an M4 and 16 GB of memory, on macOS 26.5.2. With one model loaded at a time, the largest
  (llama3.2:3b) used about 2.3 GB.

## Thinking mode
`qwen3.5:2b-q4_K_M` thinks before it answers by default. Add `--think=false` to `ollama run` (or `"think": false` in
the API) for plain, quick answers. gemma3 and llama3.2 don't think.

## Steps
```bash
./install.sh      # brew install ollama, start the service, pull the 3 models, check the size caps
./verify.sh       # version, localhost-only, models present, one chat per model, free disk -> ALL CHECKS PASSED
./measure.sh 1    # optional: speed and memory logs (ollama run --verbose, ollama ps) into ../logs/build/pass1/
./uninstall.sh    # remove the models and put the service back the way install.sh found it
```
By hand, the core is what the video shows:
```bash
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 brew install ollama   # no self-update, no "proceed?" question
ollama serve > /tmp/ollama.log 2>&1 &                             # server for this terminal session only
ollama -v
ollama run gemma3:1b
```
The server started this way stops when you close the terminal. Run the `ollama serve` line again next time.
`install.sh` uses `brew services start ollama` instead, which starts the server now and at every login (macOS lists
it under Login Items). `uninstall.sh` stops either kind.

| Model | Licence |
|---|---|
| `gemma3:1b` | Gemma Terms of Use |
| `qwen3.5:2b-q4_K_M` | Apache 2.0 |
| `llama3.2:3b` | Llama 3.2 Community License |

## Licence
- **Ollama:** MIT License (read 12 Nov 2026). Commercial use, changes and redistribution are allowed if the
  copyright notice is kept. There is no warranty.
- **The models are not covered by MIT.** Each has its own licence, listed above. The strictest is the Gemma Terms
  of Use: Google's Prohibited Use Policy applies, and it passes on to anyone you share the model with. Llama 3.2
  requires Meta's Acceptable Use Policy, and "Built with Llama" if you redistribute it.

## Safety
- Leave `OLLAMA_HOST` alone. Setting it to `0.0.0.0` puts the API, which has no password, on your network. Use
  Tailscale or WireGuard if you need to reach it from another device.

## Backup and update
- Models live in `~/.ollama/models` and can be pulled again at any time, so the only things worth backing up are
  your own Modelfiles and prompts.
- The formula doesn't auto-update. Run `brew upgrade ollama` when you choose to, then `brew services restart ollama`.
  Update `PINNED_VERSION` in the scripts to match.

## Files
- `install.sh`
- `measure.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
