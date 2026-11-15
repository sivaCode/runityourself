# The commands, in order

Run a private AI chatbot on your Mac with Ollama: real speed numbers: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Install Ollama

```sh
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 brew install ollama
ollama serve > /tmp/ollama.log 2>&1 &
ollama -v
```

### First private chat

```sh
ollama pull gemma3:1b
ollama run --verbose --nowordwrap gemma3:1b "Write three sentences explaining what a password manager does."
ollama ps
ollama stop gemma3:1b
```

### Two more models

```sh
ollama pull qwen3.5:2b-q4_K_M
ollama pull llama3.2:3b
```

### Speed compared

```sh
ollama run --verbose --nowordwrap --think=false qwen3.5:2b-q4_K_M "Write three sentences explaining what a password manager does."
ollama ps
ollama stop qwen3.5:2b-q4_K_M
ollama run --verbose --nowordwrap llama3.2:3b "Write three sentences explaining what a password manager does."
ollama ps
ollama stop llama3.2:3b
```

### Disk space

```sh
ollama list
```

### Verify

```sh
./verify.sh
```
