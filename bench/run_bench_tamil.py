"""Tamil speakers learning professional / spoken / business English.

Usage: python3 bench/run_bench_tamil.py [model ...]   (models from run_bench.MODELS)
Writes bench/results-tamil/<model>.run<N>.json  (2 runs per model)
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_bench as rb  # noqa: E402

HERE = rb.HERE
OUT = os.path.join(HERE, "results-tamil")
RUNS = 2

# ---------- 1. Role-plays: the model plays the other person, in English ----------
ROLEPLAY_SYS = (
    "Role-play for English practice. YOU are {role}. The user is {learner}, a Tamil speaker "
    "improving their English (CEFR B1). Stay in your role. Reply ONLY in clear, natural, professional "
    "English, in at most 2 short sentences. Do not correct the user's English here. "
    "End with one question that keeps the conversation going."
)
ROLEPLAYS = {
    "job_interview": {
        "role": "an HR interviewer at an IT company in Chennai",
        "learner": "a candidate for a Java developer job",
        "turns": [
            "Good morning sir. Myself Priya, I am having three years experience in Java.",
            "I am working in Infosys since 2021. I handled one banking project.",
            "My strength is I am hard worker and I will learn fast.",
        ],
    },
    "client_call": {
        "role": "a client from a UK company on a project status call",
        "learner": "a project coordinator at an Indian software vendor",
        "turns": [
            "Good evening. I will revert back regarding the delivery date by tomorrow.",
            "Actually the testing is little bit delayed because of two members are on leave.",
            "We can prepone the demo to Monday if you are okay.",
        ],
    },
    "office_small_talk": {
        "role": "a friendly colleague at the coffee machine in the office",
        "learner": "a colleague",
        "turns": [
            "Hi! Today morning I came late because of traffic only.",
            "Yes, weekend I went to my native place. My cousin brother marriage was there.",
        ],
    },
}

# ---------- 2. Corrections: typical Indian/Tamil-English mistakes, explained in Tamil ----------
CORRECT_SYS = (
    "You are an English teacher for Tamil speakers who want professional and business English. "
    "Check the learner's English sentence. Report grammar mistakes (type 'grammar') and phrases that are "
    "unclear or unprofessional in international business English (type 'style'). Only report real problems; "
    "if the sentence is already correct and professional, return an empty mistakes list and the sentence "
    "unchanged. Every fix in 'corrected' must be listed. Write each explanation as ONE short sentence in "
    "simple Tamil (Tamil script); English words may stay in English."
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
                    "type": {"type": "string", "enum": ["grammar", "style"]},
                    "explanation_tamil": {"type": "string", "maxLength": 220},
                },
                "required": ["wrong", "right", "type", "explanation_tamil"],
            },
        },
    },
    "required": ["corrected", "mistakes"],
}
CORRECTIONS = [
    {"text": "Myself Karthik and I am having two years of experience in sales.",
     "planted": ["Myself Karthik -> I am / My name is Karthik", "I am having -> I have"]},
    {"text": "I am working in this company since 2019.",
     "planted": ["am working ... since -> have been working ... since"]},
    {"text": "Please revert back to me today itself.",
     "planted": ["revert back -> get back to / reply (style)", "today itself -> today / by end of today (style)"]},
    {"text": "We discussed about the budget and he told that it is fine.",
     "planted": ["discussed about -> discussed", "told that -> said that"]},
    {"text": "Kindly do the needful and send the files.",
     "planted": ["Kindly do the needful -> Please (style; vague)"]},
    {"text": "What is your good name?",
     "planted": ["What is your good name -> May I know your name? (style)"]},
    {"text": "I have been working here for three years and I enjoy my role.", "planted": []},
    {"text": "Could you please send me the updated report by Friday?", "planted": []},
]

# ---------- 3. Help requests in Tamil script and in Tanglish ----------
HELP_SYS = (
    "You are a friendly English coach for Tamil speakers. The learner may write in Tamil script, "
    "in Tanglish (Tamil written in English letters), or in English. Give them 1-2 ready-to-use "
    "professional English sentences (or a short email if they ask for one), then one or two short lines "
    "in simple Tamil (Tamil script) explaining when to use it. Keep the whole answer short."
)
HELP = [
    {"id": "leave_tamil_script",
     "text": "மேனேஜர் கிட்ட நாளைக்கு லீவ் கேட்கணும். எப்படி professional-ஆ சொல்றது?",
     "meaning": "I need to ask my manager for leave tomorrow. How do I say it professionally?"},
    {"id": "late_apology_tamil_script",
     "text": "மீட்டிங்குக்கு 10 நிமிஷம் லேட்டா வந்துட்டேன். எப்படி மன்னிப்பு கேட்கணும்?",
     "meaning": "I came 10 minutes late to the meeting. How should I apologise?"},
    {"id": "interview_tanglish",
     "text": "naan interview la romba nervous aagiten, 'tell me about yourself' ku enna sollanum?",
     "meaning": "I get very nervous in interviews; what should I say for 'tell me about yourself'?"},
    {"id": "deadline_email_tanglish",
     "text": "client kitta deadline extend panna solli oru chinna email ezhudhi kudunga",
     "meaning": "Write me a short email asking the client to extend the deadline."},
    {"id": "casual_to_formal",
     "text": "idha professional ah maathunga: 'hey send me that report asap, need it'",
     "meaning": "Make this professional: 'hey send me that report asap, need it'"},
]


class Server:
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        os.makedirs(OUT, exist_ok=True)
        self.log = open(os.path.join(OUT, "server.log"), "a")
        self.proc = subprocess.Popen(
            ["llama-server", "-m", os.path.join(HERE, self.path), "--port", str(rb.PORT),
             "-c", "4096", "-ngl", "99", "--jinja", "--reasoning", "off"],
            stdout=self.log, stderr=subprocess.STDOUT,
        )
        rb.wait_ready(self.proc)
        return self

    def __exit__(self, *a):
        self.proc.terminate()
        self.proc.wait()
        self.log.close()


def run_once():
    out = {"roleplay": {}, "correction": [], "help": []}
    for name, rp in ROLEPLAYS.items():
        msgs = [{"role": "system", "content": ROLEPLAY_SYS.format(role=rp["role"], learner=rp["learner"])}]
        turns = []
        for t in rp["turns"]:
            msgs.append({"role": "user", "content": t})
            r = rb.chat(msgs, temperature=0.7, max_tokens=150)
            msgs.append({"role": "assistant", "content": r["text"]})
            turns.append({"learner": t, **r})
        out["roleplay"][name] = turns
    for c in CORRECTIONS:
        r = rb.chat([{"role": "system", "content": CORRECT_SYS}, {"role": "user", "content": c["text"]}],
                    temperature=0.1, schema=CORRECT_SCHEMA, max_tokens=700)
        try:
            r["parsed"] = json.loads(r["text"])
        except Exception:
            r["parsed"] = None
        out["correction"].append({"input": c["text"], "planted": c["planted"], **r})
    for h in HELP:
        r = rb.chat([{"role": "system", "content": HELP_SYS}, {"role": "user", "content": h["text"]}],
                    temperature=0.5, max_tokens=400)
        out["help"].append({"id": h["id"], "input": h["text"], "meaning": h["meaning"], **r})
    return out


if __name__ == "__main__":
    names = sys.argv[1:] or ["gemma4-e2b", "qwen3.5-4b", "qwen3.5-2b"]
    for name in names:
        print(f"== {name}", flush=True)
        with Server(rb.MODELS[name]):
            for i in range(1, RUNS + 1):
                res = run_once()
                with open(os.path.join(OUT, f"{name}.run{i}.json"), "w") as f:
                    json.dump({"model": name, "run": i, **res}, f, ensure_ascii=False, indent=1)
                print(f"  run {i} done", flush=True)
