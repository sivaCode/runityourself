# The commands, in order

Local AI on your 16 GB Mac with Ollama: 5.3 GB for an 8B model: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Three memory figures

```sh
ollama -v
ollama list
ollama run --verbose --nowordwrap gemma3:1b "Write three sentences explaining what a password manager does."
ollama ps
ps -o rss=,comm= -p "$(pgrep -x llama-server)"
```

### Swap and the GPU limit

```sh
memory_pressure | tail -1
sysctl vm.swapusage
grep -m1 recommendedMaxWorkingSetSize /tmp/ollama.log
sysctl iogpu.wired_limit_mb
ollama stop gemma3:1b
```

### What context costs

```sh
curl -s http://localhost:11434/api/generate -d '{"model":"gemma3:1b","prompt":"Say hi","stream":false,"options":{"num_ctx":32768}}' > /dev/null && ollama ps
ollama stop gemma3:1b
```

### Qwen 3.5 at 2B

```sh
ollama pull qwen3.5:2b-q4_K_M
ollama run --verbose --nowordwrap --think=false qwen3.5:2b-q4_K_M "Write three sentences explaining what a password manager does."
ollama ps
ps -o rss=,comm= -p "$(pgrep -x llama-server)"
ollama stop qwen3.5:2b-q4_K_M
ollama rm qwen3.5:2b-q4_K_M
```

### Q4 against Q8

```sh
ollama pull llama3.2:3b
ollama run --verbose --nowordwrap llama3.2:3b "Write three sentences explaining what a password manager does."
ollama ps
ollama stop llama3.2:3b
ollama rm llama3.2:3b
ollama pull llama3.2:3b-instruct-q8_0
ollama run --verbose --nowordwrap llama3.2:3b-instruct-q8_0 "Write three sentences explaining what a password manager does."
ollama ps
ollama stop llama3.2:3b-instruct-q8_0
ollama list
ollama rm llama3.2:3b-instruct-q8_0
```

### Qwen 3.5 at 4B

```sh
ollama pull qwen3.5:4b-q4_K_M
ollama run --verbose --nowordwrap --think=false qwen3.5:4b-q4_K_M "Write three sentences explaining what a password manager does."
ollama ps
ollama stop qwen3.5:4b-q4_K_M
ollama rm qwen3.5:4b-q4_K_M
```

### Llama 3.1 at 8B

```sh
ollama pull llama3.1:8b
ollama run --verbose --nowordwrap llama3.1:8b "Write three sentences explaining what a password manager does."
ollama ps
ollama stop llama3.1:8b
```

### The context ladder

```sh
curl -s http://localhost:11434/api/generate -d '{"model":"llama3.1:8b","prompt":"Say hi","stream":false,"options":{"num_ctx":8192}}' > /dev/null && ollama ps
ollama stop llama3.1:8b
curl -s http://localhost:11434/api/generate -d '{"model":"llama3.1:8b","prompt":"Say hi","stream":false,"options":{"num_ctx":16384}}' > /dev/null && ollama ps
ollama stop llama3.1:8b
curl -s http://localhost:11434/api/generate -d '{"model":"llama3.1:8b","prompt":"Say hi","stream":false,"options":{"num_ctx":32768}}' > /dev/null && ollama ps
memory_pressure | tail -1
sysctl vm.swapusage
ollama stop llama3.1:8b
ollama rm llama3.1:8b
```

### Verify

```sh
./verify.sh
```
