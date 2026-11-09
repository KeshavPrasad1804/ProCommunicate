"""Measure how much memory each model build really uses (macOS phys_footprint, the same
metric iOS uses to decide when to kill an app), under different llama.cpp settings.

Usage: python3 bench/measure_memory.py
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_bench as rb  # noqa: E402

BUILDS = ["gemma4-e2b", "gemma4-e2b-qat-q4"]
# name -> extra llama-server args
CONFIGS = {
    "test default (4 slots, ctx 4096, GPU)": ["-c", "4096", "-ngl", "99"],
    "phone (1 slot, ctx 2048, KV q8_0, GPU)": ["-c", "2048", "-np", "1", "-ngl", "99",
                                                "-ctk", "q8_0", "-ctv", "q8_0", "-fa", "on"],
    "phone + lazy embeddings (GPU)": ["-c", "2048", "-np", "1", "-ngl", "99", "-ctk", "q8_0", "-ctv", "q8_0",
                                      "-fa", "on", "-lzm", "on"],
    "phone + lazy embeddings, CPU only": ["-c", "2048", "-np", "1", "-ngl", "0", "-ctk", "q8_0", "-ctv", "q8_0",
                                          "-fa", "on", "-lzm", "on"],
    "phone, CPU only": ["-c", "2048", "-np", "1", "-ngl", "0", "-ctk", "q8_0", "-ctv", "q8_0", "-fa", "on"],
    "phone, no mmap (GPU)": ["-c", "2048", "-np", "1", "-ngl", "99", "-ctk", "q8_0", "-ctv", "q8_0",
                             "-fa", "on", "-lm", "none"],
}


def footprint(pid):
    out = subprocess.run(["footprint", str(pid)], capture_output=True, text=True).stdout
    m = re.search(r"phys_footprint:\s*([\d.]+)\s*([KMG]B)", out) or re.search(
        r"Footprint:\s*([\d.]+)\s*([KMG]B)", out)
    if not m:
        return None
    v, u = float(m.group(1)), m.group(2)
    return round(v / 1024 if u == "MB" else v if u == "GB" else v / 1024 / 1024, 2)


def rss(pid):
    kb = int(subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout)
    return round(kb / 1024 / 1024, 2)


if __name__ == "__main__":
    print(f"{'build':20} {'config':42} {'footprint GB':>12} {'RSS GB':>7} {'tok/s':>6}")
    for b in BUILDS:
        for cname, args in CONFIGS.items():
            log = open(os.devnull, "w")
            p = subprocess.Popen(["llama-server", "-m", os.path.join(rb.HERE, rb.MODELS[b]),
                                  "--port", str(rb.PORT), "--jinja", "--reasoning", "off", *args],
                                 stdout=log, stderr=log)
            try:
                rb.wait_ready(p)
                r = rb.chat([{"role": "system", "content": "You are an HR interviewer. Reply in 2 sentences."},
                             {"role": "user", "content": "Good morning. Myself Priya, I have 3 years in Java."}],
                            temperature=0.7, max_tokens=120)
                time.sleep(1)
                print(f"{b:20} {cname:42} {footprint(p.pid)!s:>12} {rss(p.pid):>7} {r['tok_per_s']:>6}", flush=True)
            finally:
                p.terminate()
                p.wait()
