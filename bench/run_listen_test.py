"""Can the app understand spoken Tamil, Hindi, Tanglish and Hinglish (and still hear Indian English verbatim)?

Compares, on the same clips:
  A. Whisper small multilingual (whisper.cpp): transcribe (auto language), transcribe (language forced), translate to English
  B. Gemma 4 E2B listening directly (llama.cpp mtmd): transcribe, and "what does the learner mean / what should they say"

Clips: bench/audio/synthetic/*.wav (macOS voices, see clips.json) and bench/audio/mine/*.m4a|wav (your recordings).
Usage: python3 bench/run_listen_test.py [synthetic|mine ...]   Writes bench/results-listen/<set>.json
"""
import glob
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "models")
WHISPER = os.path.join(MODELS, "ggml-small.bin")
GEMMA = os.path.join(MODELS, "gemma-4-E2B-it-Q4_K_M.gguf")
MMPROJ = os.path.join(MODELS, "mmproj-gemma-4-E2B-F16.gguf")
OUT = os.path.join(HERE, "results-listen")
LANG_NAME = {"ta": "Tamil", "hi": "Hindi", "en": "English"}

GEMMA_TRANSCRIBE = ("Transcribe exactly what the speaker says, word for word, in the language and script they actually use "
                    "(Tamil script for Tamil, Devanagari for Hindi, Latin letters for English words). Do not translate and do not "
                    "correct grammar mistakes. Output only the transcript.")
GEMMA_TUTOR = ("You are an English tutor for an Indian IT professional whose first language may be Tamil or Hindi. Listen to the learner. "
               "Reply in exactly two lines:\nMEANING: what the learner means or is asking, in English.\n"
               "SAY: the natural, professional English sentence they could say at work (if they asked how to say something).")


def run(cmd, timeout=300):
    t = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.stdout.strip(), round(time.time() - t, 2), p.returncode, p.stderr[-400:]


def whisper(wav, lang=None, translate=False):
    cmd = ["whisper-cli", "-m", WHISPER, "-f", wav, "-nt", "-np", "-l", lang or "auto"]
    if translate:
        cmd.append("-tr")
    out, secs, code, err = run(cmd)
    return {"text": out, "seconds": secs, **({"error": err} if code else {})}


def gemma(wav, prompt):
    """Gemma hears the clip through llama-server's OpenAI-style audio input (thinking off, like the app)."""
    import base64
    import urllib.request
    audio = base64.b64encode(open(wav, "rb").read()).decode()
    body = {"messages": [{"role": "user", "content": [
                {"type": "input_audio", "input_audio": {"data": audio, "format": "wav"}},
                {"type": "text", "text": prompt}]}],
            "temperature": 0, "max_tokens": 160}
    t = time.time()
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
        r = json.load(urllib.request.urlopen(req, timeout=300))
        return {"text": r["choices"][0]["message"]["content"].strip(), "seconds": round(time.time() - t, 2)}
    except Exception as e:  # noqa: BLE001
        return {"text": "", "seconds": round(time.time() - t, 2), "error": str(e)}


PORT = 8093


class GemmaServer:
    def __enter__(self):
        self.proc = subprocess.Popen(["llama-server", "-m", GEMMA, "--mmproj", MMPROJ, "--port", str(PORT), "-c", "4096",
                                      "-ngl", "99", "--jinja", "--reasoning", "off"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import urllib.request
        for _ in range(180):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=1)
                return self
            except Exception:  # noqa: BLE001
                time.sleep(1)
        raise RuntimeError("llama-server did not start")

    def __exit__(self, *a):
        self.proc.terminate()
        self.proc.wait()


def clips(which):
    if which == "synthetic":
        meta = {c["id"]: c for c in json.load(open(os.path.join(HERE, "audio", "synthetic", "clips.json")))}
        return [(os.path.join(HERE, "audio", "synthetic", f"{i}.wav"), m) for i, m in meta.items()]
    found = []
    folder = os.path.join(HERE, "audio", "mine")
    for path in sorted(glob.glob(os.path.join(folder, "*.m4a")) + glob.glob(os.path.join(folder, "*.wav"))):
        if path.endswith(".16k.wav"):
            continue
        wav = os.path.splitext(path)[0] + ".16k.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", path, wav], check=True)
        n = os.path.basename(path).split(".")[0]
        found.append((wav, {"id": f"mine-{n}", "lang": "en" if n in ("5", "6") else "ta", "text": "(your recording)", "meaning": ""}))
    return found


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    server = GemmaServer().__enter__()
    for which in sys.argv[1:] or ["synthetic"]:
        results = []
        for wav, meta in clips(which):
            lang = meta["lang"]
            r = {"clip": meta["id"], "lang": lang, "said": meta["text"], "meaning": meta["meaning"],
                 "whisper_auto": whisper(wav),
                 "whisper_forced": whisper(wav, lang),
                 "gemma_transcribe": gemma(wav, GEMMA_TRANSCRIBE),
                 "gemma_tutor": gemma(wav, GEMMA_TUTOR)}
            if lang != "en":
                r["whisper_translate"] = whisper(wav, lang, translate=True)
            results.append(r)
            print(f"done {meta['id']}", flush=True)
        json.dump(results, open(os.path.join(OUT, f"{which}.json"), "w"), ensure_ascii=False, indent=1)
    server.__exit__()
