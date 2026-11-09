#!/usr/bin/env python3
"""Validates lesson JSON files with the same rules as Lesson.validationProblems() in the app.

Usage: python3 tools/validate_lessons.py [lesson.json ...]   (default: every lesson)
Exit code 0 = all valid.
"""
import glob
import json
import re
import sys

ROOT = "ProCommunicate/Resources/content/ta-en"
BANNED = ["revert back", "do the needful", "today itself", "discuss about", "myself ", "i am having",
          "one doubt", "fine only", "prepone", "cousin brother", "good name", "kindly do"]


def normalize(text):
    text = text.replace("’", "'").replace("‘", "'").lower()
    text = " ".join(text.split())
    return text.strip(".!? ")


def validate(path, unit_ids):
    problems = []
    try:
        lesson = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        return [f"invalid JSON: {e}"]
    for key in ["id", "unitId", "title", "intro", "introTamil", "tamilReviewed", "phrases", "steps"]:
        if key not in lesson:
            problems.append(f"missing {key}")
    if problems:
        return problems
    if lesson["unitId"] not in unit_ids:
        problems.append(f"unknown unitId {lesson['unitId']}")
    expected_file = f"{lesson['unitId']}.json"
    if not path.endswith(expected_file):
        problems.append(f"file must be named {expected_file}")
    phrase_ids = {p["id"] for p in lesson["phrases"]}
    if len(phrase_ids) != len(lesson["phrases"]):
        problems.append("duplicate phrase ids")
    for p in lesson["phrases"]:
        for k in ["id", "text", "tamil"]:
            if not p.get(k):
                problems.append(f"phrase {p.get('id')}: missing {k}")
        if not re.search(r"[஀-௿]", p.get("tamil", "")):
            problems.append(f"phrase {p.get('id')}: tamil has no Tamil script")
        for bad in BANNED:
            if bad in p.get("text", "").lower():
                problems.append(f"phrase {p['id']}: contains banned '{bad}'")
    steps = lesson["steps"]
    if len({s["id"] for s in steps}) != len(steps):
        problems.append("duplicate step ids")
    for s in steps:
        where = f"step {s.get('id')}"
        t = s.get("type")
        if t == "learn":
            if s.get("phraseId") not in phrase_ids:
                problems.append(f"{where}: unknown phraseId")
        elif t in ("choice", "listen", "fix"):
            answer, options = s.get("answer"), s.get("options") or []
            if not answer or len(options) < 2:
                problems.append(f"{where}: needs answer and >= 2 options"); continue
            if sum(1 for o in options if normalize(o) == normalize(answer)) != 1:
                problems.append(f"{where}: exactly one option must match the answer")
            if t == "listen" and not s.get("audioText"):
                problems.append(f"{where}: listen needs audioText")
            if t == "fix":
                if not s.get("wrong"):
                    problems.append(f"{where}: fix needs wrong")
                elif s["wrong"] not in options:
                    problems.append(f"{where}: fix options must include the wrong sentence")
                if len([o for o in options if o != s.get("wrong")]) < 3:
                    problems.append(f"{where}: fix needs 3 options besides the wrong sentence")
                if not s.get("explanationTamil"):
                    problems.append(f"{where}: fix needs explanationTamil")
            if t == "choice" and not s.get("prompt"):
                problems.append(f"{where}: choice needs prompt")
        elif t == "build":
            answer, tiles = s.get("answer"), s.get("tiles") or []
            if not answer or not tiles or not s.get("promptTamil"):
                problems.append(f"{where}: build needs answer, tiles, promptTamil"); continue
            available = [normalize(x) for x in tiles]
            for word in answer.split(" "):
                w = normalize(word)
                if w in available:
                    available.remove(w)
                else:
                    problems.append(f"{where}: tile missing for '{word}'")
            if any(x.endswith((".", "?", "!")) for x in tiles):
                problems.append(f"{where}: tiles must not end with punctuation")
            if len(tiles) - len(answer.split(" ")) < 2:
                problems.append(f"{where}: build needs at least 2 distractor tiles")
        elif t == "speak":
            if not s.get("prompt"):
                problems.append(f"{where}: speak needs prompt")
            for pid in s.get("suggestedPhraseIds") or []:
                if pid not in phrase_ids:
                    problems.append(f"{where}: unknown suggested phrase {pid}")
        else:
            problems.append(f"{where}: unknown type {t}")
    counts = {k: sum(1 for s in steps if s.get("type") == k) for k in ["learn", "choice", "build", "listen", "fix", "speak"]}
    if counts["learn"] != len(lesson["phrases"]):
        problems.append("every phrase needs exactly one learn step")
    if counts["speak"] != 1 or steps[-1].get("type") != "speak":
        problems.append("exactly one speak step, at the end")
    return problems


def main():
    course = json.load(open(f"{ROOT}/course.json", encoding="utf-8"))
    unit_ids = {u["id"] for t in course["tracks"] for u in t["units"]}
    files = sys.argv[1:] or sorted(glob.glob(f"{ROOT}/lessons/*.json"))
    failed = 0
    for path in files:
        problems = validate(path, unit_ids)
        if problems:
            failed += 1
            print(f"✘ {path}")
            for p in problems:
                print(f"    - {p}")
        else:
            print(f"✔ {path}")
    print(f"\n{len(files) - failed}/{len(files)} valid")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
