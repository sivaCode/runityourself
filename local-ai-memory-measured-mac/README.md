> **Run It Yourself:** Local AI on your 16 GB Mac with Ollama: 5.3 GB for an 8B model
>
> [The commands, in order](docs/commands.md) · [What it builds](docs/architecture.html) · [References](docs/references.md)

# Local AI memory, measured: small models on a 16 GB Mac

How much memory does a local model really take on an Apple silicon Mac, and will the next one fit? These scripts
set up Ollama, then measure any model you have pulled: its size on disk, its loaded size and CPU/GPU split
(`ollama ps`), the runner's resident memory (`ps`), the system's memory pressure and swap, and its speed
(`ollama run --verbose`). They can also climb a context ladder (4096 → 8192 → … tokens) and stop at the first step
where the model no longer fits on the GPU.

Companion files for the Run It Yourself video (its link is added here once it is published).

**Status: verified.** See "Tested on" below.

## Requirements
- An Apple silicon Mac (M1 or newer) on macOS 14 Sonoma or newer, and Homebrew (https://brew.sh)
- 26 GB of free disk before you start: the largest model here is 4.9 GB, and the scripts keep 20 GB free
- No accounts, keys or passwords: Ollama's API has none, so it stays on `127.0.0.1`

## Steps
```bash
./install.sh                    # brew install ollama (if missing), a session server on 127.0.0.1, pull gemma3:1b
./verify.sh                     # version, localhost only, no login item, a real answer, a context change -> ALL CHECKS PASSED
./measure.sh gemma3:1b          # one model at the default context; results in ./measurements/gemma3_1b/
ollama pull llama3.1:8b         # 4.9 GB
./measure.sh llama3.1:8b 4096 8192 16384 32768 65536   # the context ladder; stops at the first step off the GPU
ollama rm llama3.1:8b           # pull, measure, remove: one model on disk at a time
./uninstall.sh                  # remove the models and put the Mac back the way install.sh found it
```
`install.sh` starts the server for this session only (`ollama serve`, log in `/tmp/ollama.log`). It doesn't
register a login item or a background service. After a restart, run `ollama serve > /tmp/ollama.log 2>&1 &` again.

By hand, the readings the video shows are:
```bash
ollama list                                         # size on disk
ollama ps                                           # loaded SIZE, PROCESSOR (100% GPU?), CONTEXT
ps -o rss=,comm= -p "$(pgrep -x llama-server)"      # the runner's resident memory, in KiB
memory_pressure | tail -1                           # free memory, system-wide
sysctl vm.swapusage                                 # swap in use
grep -m1 recommendedMaxWorkingSetSize /tmp/ollama.log   # the GPU memory macOS offers this Mac
```
A longer context is set per request, so nothing needs undoing afterwards:
```bash
curl -s http://localhost:11434/api/generate \
  -d '{"model":"llama3.1:8b","prompt":"Say hi","stream":false,"options":{"num_ctx":16384}}' > /dev/null && ollama ps
```

## Models measured
| Model | Licence |
|---|---|
| `gemma3:1b` | Gemma Terms of Use |
| `qwen3.5:2b-q4_K_M`, `qwen3.5:4b-q4_K_M` | Apache 2.0 |
| `llama3.2:3b` (q4_K_M) and `llama3.2:3b-instruct-q8_0` | Llama 3.2 Community License |
| `llama3.1:8b` (q4_K_M) | Llama 3.1 Community License |

qwen3.5 thinks before it answers by default. The scripts switch that off (`--think=false`, `"think": false`) so the
speeds compare like with like.

## Licence
- **Ollama:** MIT License (read 14 Nov 2026). Commercial use, changes and redistribution are allowed if the
  copyright notice is kept. There is no warranty.
- **MIT covers the Ollama app only, not the models.** Each model has its own licence (table above). The strictest
  is the Gemma Terms of Use: Google's Prohibited Use Policy applies and passes on to anyone you share the model with.
  The Llama licences require Meta's Acceptable Use Policy, Meta's permission above 700 million monthly users, and
  "Built with Llama" if you redistribute. Qwen3.5 is Apache 2.0.

## Safety
- Don't raise the GPU memory limit with `sudo sysctl iogpu.wired_limit_mb=…`. Apple doesn't document it, it needs
  sudo, and it can starve macOS of memory. The scripts only read it.
- Leave `OLLAMA_HOST` alone. `0.0.0.0` puts the password-less API on your network.

## Backup and update
- Models live in `~/.ollama/models` and can be pulled again at any time. Nothing here needs a backup.
- The formula doesn't update itself. Run `brew upgrade ollama` when you choose to, restart `ollama serve`, then set
  `PINNED_VERSION` in the scripts to match and measure again: numbers change between versions.

## Tested on
14 Nov 2026, two clean passes (install → verify → measure → uninstall), both `ALL CHECKS PASSED`: a Mac mini
(Apple M4, 16 GiB) on macOS 26.5.2, Homebrew 7.0.13, Ollama 0.40.16. install.sh + verify.sh took 23 s, and a whole
measuring pass of all six models took under 10 minutes. Measured there (`ollama ps`, default context 4096, all
100% GPU): gemma3:1b 879 MB, qwen3.5:2b 1.6 GB, llama3.2:3b 2.6 GB (q8_0: 4.0 GB), qwen3.5:4b 3.2 GB,
llama3.1:8b 5.3 GB. llama3.1:8b at a 32768 context: 9.1 GB, still 100% GPU, with memory pressure at "warn".
Your numbers will differ with your Mac, your macOS and what else is open. That's the point of `measure.sh`.

## Files
- `install.sh`
- `measure.sh`
- `uninstall.sh`
- `verify.sh`

Run the scripts at your own risk and read them first. They were tested on the Mac and versions above; yours may differ.
