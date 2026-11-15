#!/bin/bash
# Build-time measurements, written as logs.
# Usage: ./measure.sh <pass-number>      (writes ../logs/build/pass<N>/)
set -euo pipefail
PASS="${1:?pass number}"
MODELS=(gemma3:1b qwen3.5:2b-q4_K_M llama3.2:3b)
PROMPT="Write three sentences explaining what a password manager does."
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../logs/build/pass$PASS"; mkdir -p "$OUT"

{ date -u +%FT%TZ; ollama -v; sw_vers; sysctl -n machdep.cpu.brand_string hw.model hw.memsize; } > "$OUT/system.txt" 2>&1
ollama list > "$OUT/ollama-list.txt"
df -h / > "$OUT/df.txt"

for m in "${MODELS[@]}"; do
  f="$OUT/${m//[:\/]/_}"
  ollama show "$m" > "$f.show.txt" 2>&1
  # Thinking off for models that can think, so eval rates compare like with like (RESEARCH pitfall 5).
  THINK=(); grep -qi '^ *thinking' "$f.show.txt" && THINK=(--think=false)
  echo "$m think flag: ${THINK[*]:-none (model has no thinking capability)}" >> "$OUT/think-flag.txt"
  ollama stop "$m" >/dev/null 2>&1 || true
  memory_pressure > "$f.mem-before.txt" 2>&1 || true
  /usr/bin/time -l ollama run --verbose --nowordwrap ${THINK[@]+"${THINK[@]}"} "$m" "$PROMPT" \
    > "$f.answer.txt" 2> "$f.verbose.txt"
  ollama ps > "$f.ps.txt"                     # loaded size, CPU/GPU split, context
  ps -axo rss=,command= | grep -E '[o]llama (runner|serve)|[l]lama-server' > "$f.rss.txt" || true
  memory_pressure > "$f.mem-loaded.txt" 2>&1 || true
  ollama stop "$m"
done
grep -H -E 'load duration|prompt eval rate|^eval rate|^eval count|^total duration' "$OUT"/*.verbose.txt \
  | tee "$OUT/summary.txt"
grep -i 'MLX' "$OUT"/*.verbose.txt > "$OUT/mlx-warnings.txt" 2>/dev/null || true
