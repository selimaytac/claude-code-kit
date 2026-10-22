# Interleaved timing of the bash + jq + awk baseline and the one-awk status line: same input, a new turn every run.
# python3 bench.py [runs]
import json, os, resource, subprocess, sys, tempfile, time, statistics as st

RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 600
base = json.load(open("input.json"))
cmds = {"bash + jq": ["bash", "baseline.sh"], "one awk": ["awk", "-f", "../statusline.awk"]}
home = tempfile.mkdtemp()
env = dict(os.environ, HOME=home, COLUMNS="140")
wall = {k: [] for k in cmds}; cpu = {k: [] for k in cmds}
for i in range(RUNS):
    for k, cmd in cmds.items():
        d = json.loads(json.dumps(base)); d["session_id"] = "bench-" + k.replace(" ", "-").replace("+", "")
        d["context_window"]["current_usage"]["input_tokens"] += i * 100
        data = json.dumps(d).encode()
        r0 = resource.getrusage(resource.RUSAGE_CHILDREN); t0 = time.perf_counter()
        subprocess.run(cmd, input=data, stdout=subprocess.DEVNULL, env=env, check=True)
        t1 = time.perf_counter(); r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
        wall[k].append((t1 - t0) * 1000)
        cpu[k].append((r1.ru_utime - r0.ru_utime + r1.ru_stime - r0.ru_stime) * 1000)
for k in cmds:
    w = sorted(wall[k])
    print(f"{k}: wall median {st.median(w):.1f} ms, p90 {w[int(len(w) * .9)]:.1f} ms, cpu median {st.median(cpu[k]):.1f} ms")
