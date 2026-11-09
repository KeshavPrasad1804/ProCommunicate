# Hindi → English: Gemma 4 E2B check (2026-11-09)

Script: `bench/run_bench_hindi.py` · Raw output: `bench/results-hindi/gemma4-e2b.run{1,2}.json`
These are the app's own jobs, run with Hindi in place of Tamil, twice each, on a Mac with llama.cpp and thinking off.

| Job | Result |
|---|---|
| **Corrections explained in Hindi** (9 planted mistakes, 2 correct sentences) | All found in run 1, all but one well fixed in run 2. Explanations were clear and short, in Devanagari. |
| **Tap-to-explain** | Short and correct: *"Revert back" गलत है। "Get back to you" ज़्यादा natural है।* |
| **Ask in Hindi** (Devanagari and Hinglish) | Understood 5 of 5. The English was good; the Hindi lines were generic, as with Tamil. |
| **Phrase of the day with a Hindi meaning** | Good English. The Hindi was correct but too formal: *परीक्षण, एकीकरण* where people say *testing, integration*. |
| **Reading a Hinglish goal** | Focus was right 3 of 4 times: "job switch + client calls" came back as interviews, not both. It missed **kal** = tomorrow, and put **agle hafte** at 6 days. |

## Weak spots, and how the app handles them
- **"Myself Rahul and I am having…"** was corrected to *"Rahul and I have…"*, which is wrong. **"revert back"** once became just *"revert"*. The built-in mistake rules (with hand-written Hindi explanations) cover both.
- **Roman-script Hindi leaked into one explanation** (run 2). The app checks for Devanagari wherever it matters.
- **One invented "mistake"** on a correct sentence (*enjoy my role* → *find my role rewarding*). Corrections stay suggestions.
- **Formal Hindi.** Prompts ask for everyday office Hindi and to keep English work words in English.
- **Dates.** *aaj / kal / parson / agle hafte* are read by rules, not by the model. *kal* is read as tomorrow, because these are upcoming events.

**Caveat:** a native Hindi speaker should check the Hindi in the raw files and in the lessons.
