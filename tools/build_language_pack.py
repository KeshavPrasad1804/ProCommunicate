"""Builds a language pack (content/<lang>-en/) from the Tamil pack's English content plus translations.

The English side (phrases, steps, options, answers, tiles, scenarios) is shared by every language, so it's
copied from content/ta-en/. Only the learner's-language text comes from tools/translations/<lang>/:
  meetings.json, interviews.json  { lessonId: { "intro" | "phrase.<id>" | "step.<id>.prompt" | "step.<id>.explanation": text } }
  rules.json                      { ruleId: explanation }

Usage: python3 tools/build_language_pack.py hi
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CONTENT = os.path.join(ROOT, "ProCommunicate", "Resources", "content")
SOURCE = os.path.join(CONTENT, "ta-en")

LANGS = {
    "hi": {"name": "Hindi", "city": "Pune"},
}


def build(lang):
    info = LANGS[lang]
    tdir = os.path.join(ROOT, "tools", "translations", lang)
    translations = {}
    for name in ("meetings.json", "interviews.json"):
        translations.update(json.load(open(os.path.join(tdir, name), encoding="utf-8")))
    out = os.path.join(CONTENT, f"{lang}-en")
    os.makedirs(os.path.join(out, "lessons"), exist_ok=True)

    missing = []
    for fname in sorted(os.listdir(os.path.join(SOURCE, "lessons"))):
        lesson = json.load(open(os.path.join(SOURCE, "lessons", fname), encoding="utf-8"))
        t = translations.get(lesson["id"], {})

        def take(key):
            if key not in t:
                missing.append(f"{lesson['id']}: {key}")
                return ""
            return t[key]

        lesson["introNative"] = take("intro")
        lesson["nativeReviewed"] = False
        for phrase in lesson["phrases"]:
            phrase["native"] = take(f"phrase.{phrase['id']}")
        for step in lesson["steps"]:
            if "promptNative" in step:
                step["promptNative"] = take(f"step.{step['id']}.prompt")
            if "explanationNative" in step:
                step["explanationNative"] = take(f"step.{step['id']}.explanation")
        with open(os.path.join(out, "lessons", fname), "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=2)
            f.write("\n")

    course = json.load(open(os.path.join(SOURCE, "course.json"), encoding="utf-8"))
    course["id"] = course["id"].replace("ta-en", f"{lang}-en")
    course["sourceLang"] = lang
    course["title"] = course["title"].replace("Tamil", info["name"])
    with open(os.path.join(out, "course.json"), "w", encoding="utf-8") as f:
        json.dump(course, f, ensure_ascii=False, indent=2)
        f.write("\n")

    scenarios = open(os.path.join(SOURCE, "scenarios.json"), encoding="utf-8").read().replace("Chennai", info["city"])
    open(os.path.join(out, "scenarios.json"), "w", encoding="utf-8").write(scenarios)

    rules = json.load(open(os.path.join(tdir, "rules.json"), encoding="utf-8"))
    with open(os.path.join(out, "rules.json"), "w", encoding="utf-8") as f:
        json.dump(rules, f, ensure_ascii=False, indent=2)
        f.write("\n")

    if missing:
        print("Missing translations:\n  " + "\n  ".join(missing))
        sys.exit(1)
    print(f"Built content/{lang}-en: {len(os.listdir(os.path.join(out, 'lessons')))} lessons, {len(rules)} rule notes")


if __name__ == "__main__":
    for lang in sys.argv[1:] or LANGS:
        build(lang)
