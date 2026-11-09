"""Compare on-device candidate models on tutoring tasks using llama-server.

Usage: python3 bench/run_bench.py            # runs every model in MODELS
Writes bench/results/<model>.json
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = {
    "qwen3.5-2b": "models/Qwen3.5-2B-Q4_K_M.gguf",
    "qwen3.5-4b": "models/Qwen3.5-4B-Q4_K_M.gguf",
    "gemma4-e2b": "models/gemma-4-E2B-it-Q4_K_M.gguf",
    "gemma4-e2b-mobile": "models/gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf",
    "gemma4-e2b-qat-q4": "models/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf",
    "agaram-2.5b-q4": "models/agaram-2.5b-instruct-Q4_K_M.gguf",
    "agaram-2.5b-q8": "models/agaram-2.5b-instruct-Q8_0.gguf",
}
PORT = 8091

# Learner sentences with planted mistakes (the errors listed are what a good tutor must catch),
# plus one fully correct sentence per language to catch false corrections.
LANGS = {
    "Spanish": {
        "vocab": ["café", "leche", "agua", "por favor", "cuánto cuesta"],
        "turns": ["Hola, quiero un café con leche, por favor.", "Sí, y también agua. ¿Cuánto cuesta?"],
        "wrong": "Ayer yo voy al mercado y compré dos manzana. La agua está fría.",
        "planted": ["voy -> fui (past tense)", "dos manzana -> dos manzanas (plural)", "La agua -> El agua (article)"],
        "correct": "Me gustaría un té verde y un vaso de agua, por favor.",
    },
    "French": {
        "vocab": ["café", "croissant", "l'addition", "s'il vous plaît", "combien"],
        "turns": ["Bonjour, je voudrais un café, s'il vous plaît.", "Oui, et un croissant. C'est combien ?"],
        "wrong": "Hier je suis allé au marché et j'ai acheté deux pomme. Je suis 25 ans et le maison est grand.",
        "planted": ["deux pomme -> deux pommes", "Je suis 25 ans -> J'ai 25 ans", "le maison est grand -> la maison est grande"],
        "correct": "Je voudrais un thé et un verre d'eau, s'il vous plaît.",
    },
    "Hindi": {
        "vocab": ["चाय", "पानी", "कितने का", "कृपया", "मेनू"],
        "turns": ["नमस्ते, मुझे एक चाय चाहिए।", "हाँ, और पानी भी। यह कितने का है?"],
        "wrong": "कल मैं बाज़ार जाता हूँ और दो सेब खरीदा। मेरी भाई डॉक्टर है।",
        "planted": ["जाता हूँ -> गया (past tense)", "खरीदा -> मैंने ... खरीदे (ergative + plural)", "मेरी भाई -> मेरा भाई (gender)"],
        "correct": "मुझे एक कप चाय और एक गिलास पानी चाहिए।",
    },
    "Japanese": {
        "vocab": ["コーヒー", "水", "いくら", "ください", "メニュー"],
        "turns": ["こんにちは。コーヒーをください。", "はい、水もお願いします。いくらですか？"],
        "wrong": "昨日、私は店に行きます。りんごを二つを買いました。私の兄は医者がです。",
        "planted": ["行きます -> 行きました (past)", "二つを -> 二つ (double を)", "医者がです -> 医者です"],
        "correct": "すみません、紅茶を一つと水をください。",
    },
}

ROLEPLAY_SYS = (
    "Role-play: YOU are the waiter in a café. The user is the CUSTOMER, a beginner (CEFR A1) "
    "practising {lang}. Stay in the waiter role: you take orders, serve, and tell the customer prices; "
    "never ask the customer what something costs. Reply ONLY in {lang}, in at most 2 short, simple "
    "sentences. Use some of these words where natural: {vocab}. End with one simple question for the customer."
)
CORRECT_SYS = (
    "You are a precise {lang} teacher. Check the learner's {lang} sentence for grammar, spelling, "
    "gender, agreement and tense mistakes. Only report real mistakes; if the sentence is correct, "
    "return an empty mistakes list and the sentence unchanged. List every mistake you fix in 'corrected', "
    "and do not list things that are already correct. Explanations: one short sentence in simple English."
)
CORRECT_SCHEMA = {
    "type": "object",
    "properties": {
        "corrected": {"type": "string"},
        "mistakes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "wrong": {"type": "string"},
                    "right": {"type": "string"},
                    "explanation": {"type": "string", "maxLength": 200},
                },
                "required": ["wrong", "right", "explanation"],
            },
        },
    },
    "required": ["corrected", "mistakes"],
}


def post(path, body, timeout=300):
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def chat(messages, temperature, schema=None, max_tokens=300):
    body = {
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if schema:
        body["response_format"] = {"type": "json_schema", "json_schema": {"schema": schema}}
    t = time.time()
    r = post("/v1/chat/completions", body)
    msg = r["choices"][0]["message"]
    tim = r.get("timings", {})
    return {
        "text": msg.get("content", ""),
        "thinking": msg.get("reasoning_content") or "",
        "tok_per_s": round(tim.get("predicted_per_second", 0), 1),
        "prompt_tok_per_s": round(tim.get("prompt_per_second", 0), 1),
        "tokens": tim.get("predicted_n"),
        "wall_s": round(time.time() - t, 2),
    }


def wait_ready(proc):
    for _ in range(240):
        if proc.poll() is not None:
            raise RuntimeError("llama-server exited early")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            pass
        time.sleep(0.5)
    raise RuntimeError("llama-server not ready")


def run_model(name, path):
    log = open(os.path.join(HERE, "results", f"{name}.server.log"), "w")
    t0 = time.time()
    proc = subprocess.Popen(
        ["llama-server", "-m", os.path.join(HERE, path), "--port", str(PORT),
         "-c", "4096", "-ngl", "99", "--jinja", "--reasoning", "off"],
        stdout=log, stderr=subprocess.STDOUT,
    )
    try:
        wait_ready(proc)
        out = {"model": name, "file": path, "load_s": round(time.time() - t0, 1),
               "file_gb": round(os.path.getsize(os.path.join(HERE, path)) / 1e9, 2), "langs": {}}
        for lang, d in LANGS.items():
            sys_rp = ROLEPLAY_SYS.format(lang=lang, vocab=", ".join(d["vocab"]))
            msgs = [{"role": "system", "content": sys_rp}]
            rp = []
            for turn in d["turns"]:
                msgs.append({"role": "user", "content": turn})
                r = chat(msgs, temperature=0.7, max_tokens=120)
                msgs.append({"role": "assistant", "content": r["text"]})
                rp.append({"learner": turn, **r})
            corr = {}
            for kind in ("wrong", "correct"):
                r = chat(
                    [{"role": "system", "content": CORRECT_SYS.format(lang=lang)},
                     {"role": "user", "content": d[kind]}],
                    temperature=0.1, schema=CORRECT_SCHEMA, max_tokens=500,
                )
                try:
                    r["parsed"] = json.loads(r["text"])
                except Exception:
                    r["parsed"] = None
                corr[kind] = {"input": d[kind], **r}
            out["langs"][lang] = {"roleplay": rp, "correction": corr, "planted": d["planted"]}
            print(f"  {name} {lang} done", flush=True)
        return out
    finally:
        proc.terminate()
        proc.wait()
        log.close()


if __name__ == "__main__":
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    only = sys.argv[1:] or list(MODELS)
    for name in only:
        print(f"== {name}", flush=True)
        res = run_model(name, MODELS[name])
        with open(os.path.join(HERE, "results", f"{name}.json"), "w") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
