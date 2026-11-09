"""Interview mode: check each spoken answer as it comes in, then build the final feedback
from the saved mistakes (not from the whole transcript).

Usage: python3 bench/interview_feedback_test.py [variant]
  variant "full"  = original correction prompt (all problems)
  variant "top3"  = prompt asks for the 3 most important problems (no schema limit)
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_bench as rb  # noqa: E402
import run_bench_tamil as rt  # noqa: E402
from measure_context import ANSWERS  # noqa: E402

TOP3 = (rt.CORRECT_SYS + " Report ONLY the 3 most important problems: grammar mistakes and common "
        "Indian-English phrases first. Ignore small word-choice preferences.")
FEEDBACK_SYS = (
    "You are an English coach for Tamil speakers. Using ONLY the list of mistakes the candidate made in a "
    "mock interview, write short feedback: 2 sentences on their overall English, then the 3 most important "
    "habits to fix, each with the candidate's own wrong phrase and the correct phrase. Do not mention "
    "anything that is not in the list (no pronunciation, no pauses)."
)


LEAN_SCHEMA = {
    "type": "object",
    "properties": {"mistakes": {"type": "array", "items": {
        "type": "object",
        "properties": {"wrong": {"type": "string"}, "right": {"type": "string"},
                       "type": {"type": "string", "enum": ["grammar", "style"]},
                       "explanation_tamil": {"type": "string", "maxLength": 220}},
        "required": ["wrong", "right", "type", "explanation_tamil"]}}},
    "required": ["mistakes"],
}
LEAN = TOP3.replace("Every fix in 'corrected' must be listed. ", "").replace(
    "return an empty mistakes list and the sentence unchanged", "return an empty mistakes list") + \
    " Quote 'wrong' exactly from the learner's text, only the few words that are wrong."


def main(variant):
    sys_prompt = {"top3": TOP3, "lean": LEAN}.get(variant, rt.CORRECT_SYS)
    schema = LEAN_SCHEMA if variant == "lean" else rt.CORRECT_SCHEMA
    p = subprocess.Popen(["llama-server", "-m", os.path.join(rb.HERE, rb.MODELS["gemma4-e2b"]), "--port",
                          str(rb.PORT), "--jinja", "--reasoning", "off", "-c", "4096", "-np", "1", "-ngl", "99",
                          "-lzm", "on"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        rb.wait_ready(p)
        found, times = [], []
        for a in ANSWERS:
            t = time.time()
            r = rb.chat([{"role": "system", "content": sys_prompt}, {"role": "user", "content": a}],
                        temperature=0.1, schema=schema, max_tokens=1000)
            times.append(time.time() - t)
            try:
                ms = [m for m in json.loads(r["text"])["mistakes"] if m["wrong"].strip() != m["right"].strip()]
            except Exception:
                ms = []
                print("   (unfinished JSON)", repr(r["text"][-200:]))
            found += ms
            print(f"--- answer ({len(a.split())} words): {times[-1]:.1f}s, {r['tokens']} tokens out, {len(ms)} mistakes")
            for m in ms:
                print(f"   {m['type']:7} | {m['wrong']} -> {m['right']} | {m['explanation_tamil']}")
        lst = "\n".join(f"- {m['wrong']} -> {m['right']} ({m['type']})" for m in found)
        t = time.time()
        r = rb.chat([{"role": "system", "content": FEEDBACK_SYS}, {"role": "user", "content": lst}],
                    temperature=0.3, max_tokens=350)
        print(f"\n=== FINAL FEEDBACK from {len(found)} saved mistakes ({time.time()-t:.1f}s) ===\n{r['text']}")
        print(f"\navg check time per answer on Mac: {sum(times)/len(times):.1f}s")
    finally:
        p.terminate()
        p.wait()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "top3")
