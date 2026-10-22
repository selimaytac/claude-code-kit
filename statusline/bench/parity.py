# Checks that statusline.awk prints the same line and keeps the same state files as baseline.sh,
# over random sessions (null current_usage after /compact, 200k and 1M windows, with and without rate limits).
# python3 parity.py
import json, os, random, subprocess, tempfile

base = json.load(open("input.json"))
for w in ("five_hour", "seven_day"): del base["rate_limits"][w]["resets_at"]  # reset times are new in the awk version
base.pop("prompt_cache", None)  # so is the cache timer


def run(cmd, d, home):
    return subprocess.run(cmd, input=json.dumps(d), capture_output=True, text=True, env=dict(os.environ, HOME=home)).stdout


def state(home, sid, suffix=""):
    p = f"{home}/.claude/statusline-state/{sid}{suffix}"
    return open(p).read() if os.path.exists(p) else ""


same = diff = 0
for trial in range(40):
    homes = (tempfile.mkdtemp(), tempfile.mkdtemp())
    rng = random.Random(trial); sid = f"s{trial}"
    for step in range(12):
        d = json.loads(json.dumps(base)); d["session_id"] = sid
        cw = d["context_window"]; cw["context_window_size"] = rng.choice([200000, 1000000]); cw.pop("used_percentage", None)
        if rng.random() < 0.15: cw["current_usage"] = None; cw["total_input_tokens"] = rng.randint(1000, 190000)
        else: cw["current_usage"]["cache_read_input_tokens"] = rng.randint(0, 180000)
        if rng.random() < 0.3: d.pop("rate_limits")
        else: d["rate_limits"]["five_hour"]["used_percentage"] = rng.randint(0, 100)
        if rng.random() < 0.2: d["cost"]["total_cost_usd"] = round(rng.random() * 99, 2)
        a = run(["bash", "baseline.sh"], d, homes[0]); b = run(["awk", "-f", "../statusline.awk"], d, homes[1])
        if a == b and all(state(homes[0], sid, s) == state(homes[1], sid, s) for s in ("", ".size")): same += 1
        else:
            diff += 1
            if diff < 4: print("DIFF", trial, step, repr(a), repr(b))
print("same", same, "diff", diff)
