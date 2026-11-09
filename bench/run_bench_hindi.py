"""Hindi speakers learning professional / business English: can Gemma 4 E2B do the app's Hindi jobs?

Mirrors the app's prompts (TutorPrompts, Ask in Hindi, AdaptiveJobs) with Hindi in place of Tamil.
Usage: python3 bench/run_bench_hindi.py      Writes bench/results-hindi/gemma4-e2b.run<N>.json
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_bench as rb  # noqa: E402
from run_bench_tamil import Server  # noqa: E402

OUT = os.path.join(rb.HERE, "results-hindi")
RUNS = 2

# 1. Corrections explained in Hindi (Devanagari): same planted Indian-English mistakes as the Tamil test.
CORRECT_SYS = (
    "You are an English teacher for Hindi speakers who want professional and business English. "
    "Check the learner's English sentence. Report grammar mistakes (type 'grammar') and phrases that are "
    "unclear or unprofessional in international business English (type 'style'). Only report real problems; "
    "if the sentence is already correct and professional, return an empty mistakes list and the sentence "
    "unchanged. Every fix in 'corrected' must be listed. Write each explanation as ONE short sentence in "
    "simple Hindi (Devanagari script); English words may stay in English."
)
CORRECT_SCHEMA = {
    "type": "object",
    "properties": {
        "corrected": {"type": "string"},
        "mistakes": {"type": "array", "items": {"type": "object", "properties": {
            "wrong": {"type": "string"}, "right": {"type": "string"},
            "type": {"type": "string", "enum": ["grammar", "style"]},
            "explanation_hindi": {"type": "string", "maxLength": 220}},
            "required": ["wrong", "right", "type", "explanation_hindi"]}},
    },
    "required": ["corrected", "mistakes"],
}
CORRECTIONS = [
    {"text": "Myself Rahul and I am having two years of experience in sales.",
     "planted": ["Myself Rahul -> I am Rahul", "I am having -> I have"]},
    {"text": "I am working in this company since 2019.", "planted": ["am working since -> have been working since"]},
    {"text": "Please revert back to me today itself.", "planted": ["revert back -> get back to", "today itself -> today"]},
    {"text": "We discussed about the budget and he told that it is fine.", "planted": ["discussed about", "told that -> said"]},
    {"text": "Kindly do the needful and send the files.", "planted": ["do the needful (style)"]},
    {"text": "What is your good name?", "planted": ["good name (style)"]},
    {"text": "I have been working here for three years and I enjoy my role.", "planted": []},
    {"text": "Could you please send me the updated report by Friday?", "planted": []},
]

# 2. Tap-to-explain (the app's explainIn<Language> prompt).
EXPLAIN_SYS = ("You are an English coach for Hindi speakers. Explain the correction in ONE or TWO short sentences "
               "of simple Hindi (Devanagari script). English words may stay in English. No greeting, no extra text.")
EXPLAIN = [
    "Wrong: \"I will revert back by EOD.\"\nRight: \"I'll get back to you by end of day.\"\nWhy: \"Revert back\" is Indian English; \"get back to you\" is natural.",
    "Wrong: \"Can we prepone the call?\"\nRight: \"Can we move the call earlier?\"\nWhy: \"Prepone\" is not used outside India.",
]

# 3. Ask in Hindi: Devanagari and Hinglish.
HELP_SYS = (
    "You are a friendly English coach for Hindi speakers. The learner may write in Hindi (Devanagari), "
    "in Hinglish (Hindi written in English letters), or in English. Give them 1-2 ready-to-use professional "
    "English sentences (or a short email if they ask for one), then one or two short lines in simple Hindi "
    "(Devanagari script) explaining when to use it. Keep the whole answer short."
)
HELP = [
    {"id": "leave_devanagari", "text": "मैनेजर से कल की छुट्टी माँगनी है। professional तरीके से कैसे बोलूँ?",
     "meaning": "I need to ask my manager for leave tomorrow."},
    {"id": "late_devanagari", "text": "मीटिंग में 10 मिनट लेट हो गया। माफ़ी कैसे माँगूँ?", "meaning": "Late 10 min; how to apologise?"},
    {"id": "interview_hinglish", "text": "interview mein bahut nervous ho jata hoon, 'tell me about yourself' mein kya bolun?",
     "meaning": "Nervous in interviews; what to say for tell me about yourself?"},
    {"id": "deadline_hinglish", "text": "client ko deadline extend karne ke liye ek chhota email likh do",
     "meaning": "Short email asking the client to extend the deadline."},
    {"id": "casual_hinglish", "text": "isko professional bana do: 'hey send me that report asap, need it'",
     "meaning": "Make this professional."},
]

# 4. Phrase of the day with a Hindi meaning (AdaptiveJobs.phraseUser, Hindi).
PHRASE_SYS = ("You write English speaking practice for a Hindi-speaking IT professional (about CEFR B1–B2) who wants to "
              "sound natural and professional at work. Use simple, natural, polite international business English. "
              "Never use Indian-English phrases like revert back, do the needful, prepone, today itself, discuss about or "
              "\"I have one doubt\". Reply only with the JSON.")
PHRASE_SCHEMA = {"type": "object", "properties": {"english": {"type": "string"}, "hindi": {"type": "string"},
                                                   "when": {"type": "string"}}, "required": ["english", "hindi", "when"]}
PHRASE_USERS = [
    "About the learner: They work as a QA engineer at Wipro. Current project: a retail mobile app for a US client.\n"
    "Skill to practise: Giving a status update. Say what's done, what's next and any risk.\n"
    "Write ONE new sentence (8 to 20 words) the learner could really say at work this week, about their own project.\n"
    "\"english\": the sentence. \"hindi\": its meaning in simple spoken Hindi, in Devanagari. \"when\": when to say it, in at most 12 simple English words.",
    "About the learner: They work as a Java developer at TCS. They are preparing for: product company interviews.\n"
    "Skill to practise: Talking about yourself. Introduce your background clearly.\n"
    "Write ONE new sentence (8 to 20 words) the learner could really say in an interview.\n"
    "\"english\": the sentence. \"hindi\": its meaning in simple spoken Hindi, in Devanagari. \"when\": when to say it, in at most 12 simple English words.",
]

# 5. Reading a Hinglish goal (AdaptiveJobs.focusUser).
FOCUS_SCHEMA = {"type": "object", "properties": {
    "focus": {"type": "string", "enum": ["meetings", "interviews", "both"]}, "event": {"type": "string"},
    "days": {"type": "integer"}}, "required": ["focus", "event", "days"]}
FOCUS = ["kal client ke saath demo meeting hai", "agle hafte Flipkart ka interview hai",
         "roz US client ke calls mein bolne mein dikkat hoti hai", "job switch karna hai aur abhi client calls bhi hain"]


def run_once():
    out = {"correction": [], "explain": [], "help": [], "phrase": [], "focus": []}
    for c in CORRECTIONS:
        r = rb.chat([{"role": "system", "content": CORRECT_SYS}, {"role": "user", "content": c["text"]}],
                    temperature=0.1, schema=CORRECT_SCHEMA, max_tokens=700)
        try:
            r["parsed"] = json.loads(r["text"])
        except Exception:
            r["parsed"] = None
        out["correction"].append({"input": c["text"], "planted": c["planted"], **r})
    for e in EXPLAIN:
        out["explain"].append({"input": e, **rb.chat([{"role": "system", "content": EXPLAIN_SYS},
                                                      {"role": "user", "content": e}], temperature=0.2, max_tokens=160)})
    for h in HELP:
        r = rb.chat([{"role": "system", "content": HELP_SYS}, {"role": "user", "content": h["text"]}],
                    temperature=0.5, max_tokens=400)
        out["help"].append({"id": h["id"], "input": h["text"], "meaning": h["meaning"], **r})
    for p in PHRASE_USERS:
        out["phrase"].append({"input": p, **rb.chat([{"role": "system", "content": PHRASE_SYS}, {"role": "user", "content": p}],
                                                    temperature=0.3, schema=PHRASE_SCHEMA, max_tokens=260)})
    for goal in FOCUS:
        user = (f'The learner\'s goal (English, Hindi or Hinglish): "{goal}"\nToday is Monday 9 November 2026.\n'
                '"focus": "interviews" if it is only about job interviews or changing jobs, "meetings" if it is only about '
                'meetings, calls or work at their current job, "both" if it mentions both.\n'
                '"event": if the goal mentions ONE specific upcoming meeting, presentation or interview, a short title for it '
                'in English (at most 8 words), otherwise "".\n"days": how many days from today until that event, or -1 if not known.')
        out["focus"].append({"input": goal, **rb.chat([{"role": "system", "content": "You read a learner's goal and classify it. Reply only with the JSON."},
                                                       {"role": "user", "content": user}], temperature=0.3, schema=FOCUS_SCHEMA, max_tokens=120)})
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    with Server(rb.MODELS["gemma4-e2b"]):
        for i in range(1, RUNS + 1):
            res = run_once()
            with open(os.path.join(OUT, f"gemma4-e2b.run{i}.json"), "w") as f:
                json.dump({"model": "gemma4-e2b", "run": i, **res}, f, ensure_ascii=False, indent=1)
            print(f"run {i} done", flush=True)
