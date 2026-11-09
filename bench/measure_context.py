"""How much memory and speed does a long mock interview cost?

Builds a realistic interview transcript (system prompt with job + rubric, then many Q/A turns with
spoken-length learner answers), fills the context to different sizes, and measures memory
(phys_footprint / RSS) plus prompt-processing and generation speed with phone-style settings.

Usage: python3 bench/measure_context.py
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_bench as rb  # noqa: E402
from measure_memory import footprint, rss  # noqa: E402

MODEL = rb.MODELS["gemma4-e2b"]

SYSTEM = (
    "Mock job interview for English practice. YOU are Meena, a senior HR interviewer at a Chennai IT "
    "services company, interviewing a candidate for a Java Developer (3-5 years) role. The candidate is a "
    "Tamil speaker improving their professional English (CEFR B1). Job: build and maintain Spring Boot "
    "microservices for banking clients, work with REST APIs, SQL databases, CI/CD and agile teams, and "
    "talk directly to UK clients. Ask one question at a time, follow up on what the candidate said earlier, "
    "keep each reply to 2-3 sentences. Cover: introduction, current role, projects, technical skills, "
    "teamwork, a conflict, client communication, strengths and weaknesses, salary expectations, notice "
    "period, and questions for us. At the end, when asked, give feedback on the candidate's English: "
    "fluency, grammar, professional vocabulary, and confidence, with 3 concrete improvements."
)
# Spoken answers are long: 60-150 words each, with typical Indian-English patterns.
ANSWERS = [
    "Good morning madam. Myself Priya Ramesh, I am from Coimbatore. I completed my B.E. in Computer Science in 2019 and from then I am working as Java developer. Currently I am working in Infosys since 2021 in the banking domain. I am having good knowledge in Spring Boot, microservices and Oracle database. In my free time I like to read technical blogs and play badminton.",
    "In my current role I am handling the payments module for one UK bank. Daily I am attending the stand-up call, then I will pick the user stories from Jira and do the development. After that I will write unit test cases using JUnit and Mockito and raise the pull request. Also I am coordinating with the testing team and sometimes I will join the client call when my lead is on leave.",
    "Recently I handled one project for loan processing. The old system was a monolith and it was very slow, so we split it into six microservices. I developed the eligibility service and the document upload service. We used Spring Boot, Kafka for the events and PostgreSQL. After the migration the response time came down from eight seconds to around one and half seconds, so the client was very happy.",
    "In my team there was one issue where the developer and the tester were fighting about one defect. The tester told it is a bug and the developer told it is working as per the requirement. I called both of them for a small meeting and we checked the requirement document together with the business analyst. Finally we found the requirement itself was not clear, so we raised a clarification to the client and the problem got solved.",
    "When I talk to the UK client, first I will prepare the points before the call. Sometimes I feel little bit nervous because their accent is fast, so I will ask them to repeat politely. After the call I will send the minutes of meeting by mail so that everybody is in the same page. I am trying to improve my spoken English by watching English news and practising with my friends.",
    "My strength is I am a quick learner and I am very dedicated to my work. For example, when our project moved to Kubernetes, I learnt it within two weeks and helped my team members also. My weakness is sometimes I take too much work and I will not say no, so I will stay late. Now I am learning to prioritise the tasks and discuss with my lead before accepting extra work.",
]
QUESTIONS = [
    "Thank you, Priya. Could you tell me more about your current role and your day-to-day responsibilities?",
    "That sounds like solid experience. Can you walk me through a recent project you are proud of and your exact contribution?",
    "Impressive results. Tell me about a time you had a disagreement within your team and how you handled it.",
    "Good approach. Since this role involves UK clients, how do you usually manage client communication?",
    "Thanks for sharing that. What would you say are your main strengths and one area you are working to improve?",
    "Thank you. What are your salary expectations, and what is your current notice period?",
]


def build_messages(target_tokens):
    msgs = [{"role": "system", "content": SYSTEM}, {"role": "assistant", "content": "Good morning! Thank you for coming in today. Could you please introduce yourself?"}]
    i = 0
    while True:
        msgs.append({"role": "user", "content": ANSWERS[i % len(ANSWERS)]})
        msgs.append({"role": "assistant", "content": QUESTIONS[i % len(QUESTIONS)]})
        i += 1
        # ~1 token per 4.2 chars for this English text (checked against the tokenizer below)
        if sum(len(m["content"]) for m in msgs) / 4.2 >= target_tokens:
            break
    msgs.append({"role": "user", "content": "Thank you for the interview. Can you please give me feedback on my English?"})
    return msgs, i


def tokens_of(msgs):
    body = {"messages": msgs, "chat_template_kwargs": {"enable_thinking": False}}
    r = rb.post("/apply-template", body)
    t = rb.post("/tokenize", {"content": r["prompt"]})
    return len(t["tokens"])


if __name__ == "__main__":
    print(f"{'ctx':>6} {'filled':>7} {'Q&A turns':>9} {'footprint GB':>12} {'RSS GB':>7} {'prompt tok/s':>12} {'gen tok/s':>9} {'1st token s':>11}")
    for ctx, fill in [(2048, 1700), (4096, 3600), (8192, 7500), (16384, 15000)]:
        p = subprocess.Popen(["llama-server", "-m", os.path.join(rb.HERE, MODEL), "--port", str(rb.PORT),
                              "--jinja", "--reasoning", "off", "-c", str(ctx), "-np", "1", "-ngl", "99",
                              "-ctk", "q8_0", "-ctv", "q8_0", "-fa", "on", "-lzm", "on"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            rb.wait_ready(p)
            msgs, turns = build_messages(fill)
            while tokens_of(msgs) > ctx - 300:      # leave room for the feedback reply
                msgs = msgs[:2] + msgs[4:]
                turns -= 1
            n = tokens_of(msgs)
            t0 = time.time()
            r = rb.chat(msgs, temperature=0.3, max_tokens=250)
            time.sleep(1)
            first = round(n / r["prompt_tok_per_s"], 1) if r["prompt_tok_per_s"] else None
            print(f"{ctx:>6} {n:>7} {turns:>9} {footprint(p.pid)!s:>12} {rss(p.pid):>7} {r['prompt_tok_per_s']:>12} {r['tok_per_s']:>9} {first!s:>11}", flush=True)
            if ctx == 8192:
                with open(os.path.join(rb.HERE, "results", "interview_feedback_8k.txt"), "w") as f:
                    f.write(r["text"])
        finally:
            p.terminate()
            p.wait()
