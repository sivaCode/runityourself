#!/bin/bash
# Measure one installed model on this Mac: disk size, loaded size, CPU/GPU split, context, the runner's resident
# memory, system memory pressure and swap, and speed. Optionally climbs a context ladder.
#
#   ./measure.sh <model> [num_ctx …]
#   ./measure.sh gemma3:1b                          # one run at the default context (4096 on a 16 GB Mac)
#   ./measure.sh llama3.1:8b 4096 8192 16384 32768  # the context ladder, one load per step
#
# Results go to $OUT/<model>/ (default ./measurements). One model is loaded at a time: every loaded model is
# stopped first. The ladder stops at the first step where the model is no longer 100% on the GPU, memory pressure
# leaves "normal", or swap grows by more than 256 MB; that step is reported as measured. Nothing system-wide is
# changed: the context is set per request (options.num_ctx), so there is nothing to undo afterwards.
set -euo pipefail
MODEL="${1:?usage: measure.sh <model> [num_ctx …]}"; shift
OUT="${OUT:-./measurements}"
export MEASURE_PROMPT="${PROMPT:-Write three sentences explaining what a password manager does.}"
export SERVER_LOG="${SERVER_LOG:-/tmp/ollama.log}"
API="http://127.0.0.1:11434"
D="$OUT/${MODEL//[:\/]/_}"; mkdir -p "$D"
curl -fsS --max-time 3 "$API/api/version" >/dev/null || { echo "no Ollama server on $API (start it: ollama serve &)" >&2; exit 1; }

# 1 s sampler: time, runner RSS (KiB, all llama-server processes), free memory %, pressure level, swap used (MB)
sampler() {
  printf 'epoch\trunner_rss_kib\tfree_pct\tpressure_level\tswap_used_mb\n'
  while :; do
    rss="$(ps -axo rss=,comm= | awk '/llama-server$/ {s+=$1} END {print s+0}')"
    free="$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {sub("%","",$2); print $2}')"
    lvl="$(sysctl -n kern.memorystatus_vm_pressure_level)"
    swap="$(sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used") {v=$(i+2); sub("M","",v); print v}}')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$rss" "$free" "$lvl" "$swap"
    sleep 1
  done
}
sampler > "$D/samples.tsv" 2>/dev/null &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null || true' EXIT

/usr/bin/python3 - "$API" "$MODEL" "$D" "$@" <<'PY'
import json, os, re, subprocess, sys, time, urllib.request
api, model, d, ladder = sys.argv[1], sys.argv[2], sys.argv[3], [int(x) for x in sys.argv[4:]]
prompt, slog = os.environ["MEASURE_PROMPT"], os.environ["SERVER_LOG"]
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)")

def call(path, body=None, timeout=600):
    req = urllib.request.Request(api + path, json.dumps(body).encode() if body is not None else None,
                                 {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))
def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout
def save(name, text):
    open(os.path.join(d, name), "w").write(text)
def loaded():
    return call("/api/ps")["models"]
def unload_all():
    for m in loaded():
        subprocess.run(["ollama", "stop", m["name"]], capture_output=True)
    for _ in range(30):
        if not loaded(): return
        time.sleep(1)
    sys.exit("models still loaded after ollama stop")
def runner_rss_kib():
    return sum(int(l.split()[0]) for l in sh("ps", "-axo", "rss=,comm=").splitlines() if l.rstrip().endswith("llama-server"))
def system():
    free = re.search(r"free percentage: (\d+)%", sh("memory_pressure"))
    swap = re.search(r"used = ([\d.]+)M", sh("sysctl", "-n", "vm.swapusage"))
    return {"free_pct": int(free.group(1)) if free else None,
            "pressure_level": int(sh("sysctl", "-n", "kern.memorystatus_vm_pressure_level").strip() or 0),
            "swap_used_mb": float(swap.group(1)) if swap else None}
def log_size():
    return os.path.getsize(slog) if os.path.exists(slog) else 0
def log_lines_since(off, pats):
    if not os.path.exists(slog): return []
    with open(slog, "rb") as f:
        f.seek(off); text = f.read().decode("utf-8", "replace")
    return [l for l in text.splitlines() if any(p in l for p in pats)]
LOGPATS = ("memory breakdown", "MTL0 (", "Host   ", "llama_kv_cache", "offloaded", "n_ctx  ", "n_ctx_seq", "fit",
           "recommendedMaxWorkingSetSize", "system memory", "gpu memory", "level=WARN", "level=ERROR")
def snapshot(tag, extra):
    ps = [m for m in loaded() if m["name"] == model]
    p = ps[0] if ps else {}
    size, vram = p.get("size", 0), p.get("size_vram", 0)
    r = {"model": model, "step": tag, **extra,
         "loaded_size_bytes": size, "size_vram_bytes": vram,
         "gpu_pct": round(100 * vram / size) if size else None,
         "context_length": p.get("context_length"), "runner": p.get("runner"),
         "runner_rss_kib": runner_rss_kib(), **system()}
    save(f"{tag}.ollama-ps.txt", sh("ollama", "ps"))
    save(f"{tag}.api-ps.json", json.dumps(p, indent=1))
    return r

show = call("/api/show", {"model": model})
caps = show.get("capabilities", [])
think = "thinking" in caps
save("show.txt", sh("ollama", "show", model))
save("license-head.txt", "\n".join(sh("ollama", "show", "--license", model).splitlines()[:12]) + "\n")
disk = {m["name"]: m["size"] for m in call("/api/tags")["models"]}.get(model)
save("ollama-list.txt", sh("ollama", "list"))
info = {"model": model, "disk_bytes": disk, "capabilities": caps, "think_off": think,
        "details": show.get("details"), "prompt": prompt}
results = []

# A. The CLI run, exactly as typed on camera (default context), timings from --verbose.
unload_all()
base = system(); off = log_size(); t0 = time.time()
cmd = ["ollama", "run", "--verbose", "--nowordwrap"] + (["--think=false"] if think else []) + [model, prompt]
p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
save("cli.answer.txt", ansi.sub("", p.stdout)); save("cli.verbose.txt", ansi.sub("", p.stderr))
v = {m.group(1): m.group(2).strip() for m in (re.match(r"^\s*((?:total|load|prompt eval|eval) (?:duration|count|rate)):\s+(.*)$", l)
                                               for l in ansi.sub("", p.stderr).splitlines()) if m}
r = snapshot("cli-default", {"method": " ".join(cmd[:-1]) + ' "<prompt>"', "wall_s": round(time.time() - t0, 2),
                             "verbose": v, "before": base})
save("cli-default.server-log.txt", "\n".join(log_lines_since(off, LOGPATS)) + "\n")
results.append(r)
print(f"{model} cli: {v.get('eval rate')} | ps {r['loaded_size_bytes']} B, {r['gpu_pct']}% GPU, ctx {r['context_length']}"
      f" | runner RSS {r['runner_rss_kib']} KiB | free {r['free_pct']}% level {r['pressure_level']} swap {r['swap_used_mb']} MB")

# B. The context ladder (API, one fresh load per step, same prompt, fixed seed).
for ctx in ladder:
    unload_all()
    base = system(); off = log_size(); t0 = time.time()
    body = {"model": model, "prompt": prompt, "stream": False,
            "options": {"num_ctx": ctx, "temperature": 0, "seed": 1, "num_predict": 128}}
    if think: body["think"] = False
    try:
        g = call("/api/generate", body, timeout=900); err = None
    except Exception as e:      # a refusal is a result too
        g, err = {}, f"{type(e).__name__}: {getattr(e, 'read', lambda: b'')().decode()[:300] or e}"
    speed = {k: g.get(k) for k in ("load_duration", "prompt_eval_count", "prompt_eval_duration", "eval_count", "eval_duration")}
    if g.get("eval_duration"): speed["eval_rate_tps"] = round(g["eval_count"] / (g["eval_duration"] / 1e9), 2)
    if g.get("prompt_eval_duration"): speed["prompt_eval_rate_tps"] = round(g["prompt_eval_count"] / (g["prompt_eval_duration"] / 1e9), 2)
    r = snapshot(f"ctx-{ctx}", {"method": "POST /api/generate options.num_ctx", "num_ctx": ctx, "error": err,
                                "wall_s": round(time.time() - t0, 2), "speed": speed, "before": base,
                                "answer": (g.get("response") or "")[:400]})
    save(f"ctx-{ctx}.server-log.txt", "\n".join(log_lines_since(off, LOGPATS)) + "\n")
    results.append(r)
    grew = (r["swap_used_mb"] or 0) - (base["swap_used_mb"] or 0)
    print(f"{model} ctx {ctx}: {speed.get('eval_rate_tps')} tok/s | ps {r['loaded_size_bytes']} B, {r['gpu_pct']}% GPU,"
          f" ctx {r['context_length']} | runner RSS {r['runner_rss_kib']} KiB | free {r['free_pct']}% level"
          f" {r['pressure_level']} swap {r['swap_used_mb']} MB ({grew:+.0f}){' | ' + err if err else ''}")
    if err or r["gpu_pct"] != 100 or r["pressure_level"] != 1 or grew > 256:
        print(f"{model}: ladder stopped at {ctx} (near the limit: reported as measured)")
        break

unload_all()
save("result.json", json.dumps({"info": info, "results": results}, indent=1))
PY
kill $SAMPLER 2>/dev/null || true
awk -F'\t' 'NR>1 && $2>m {m=$2} NR>1 && ($3<f || f=="") {f=$3} NR>1 && $5>s {s=$5}
  END {printf "sampler peak: runner RSS %d KiB, lowest free %s%%, highest swap used %s MB\n", m, f, s}' "$D/samples.tsv" \
  | tee "$D/peak.txt"
