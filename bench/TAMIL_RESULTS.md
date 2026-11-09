# Tamil → English model test (2026-11-09)

Script: `bench/run_bench_tamil.py` · Raw output: `bench/results-tamil/<model>.run{1,2}.json`
Every model got the same prompts, run twice, on an Apple M5 Mac with llama.cpp, thinking off.

## What was tested
1. **Role-play in English** (8 turns): HR job interview, UK client status call, office small talk. The learner's lines contain typical Indian-English mistakes; the model must stay in role and reply in clear, professional English.
2. **Corrections, explained in Tamil** (8 sentences, 9 planted problems + 2 correct sentences): *Myself Karthik…*, *I am having…*, *working … since 2019*, *revert back*, *today itself*, *discussed about*, *told that*, *do the needful*, *good name*.
3. **Help requests in Tamil script and Tanglish** (5): asking for leave, apologising for being late, "tell me about yourself", a deadline-extension email, rewriting a casual message professionally.

## Scores

| | Gemma 4 E2B ✅ | Qwen 3.5 4B | Qwen 3.5 2B |
|---|---|---|---|
| Role-play English | Natural, always 1–2 sentences, stays in role | Natural but long; some odd turns | Invents facts ("deadline is actually next Friday") |
| Planted problems fixed (of 9, avg of 2 runs) | **8.5** | ~7 | ~6.5 |
| Invented mistakes on correct sentences | 0 | 0 (+ nonsense extra items such as *"in sales → sales"*) | 0 |
| Tamil explanations | **Correct, clear, short** | Often wrong words (*"பொருளாதாரத் துறையில்"*, *"தொழில்முறைத் தமிழில்"*), made-up word *மெய்ம்* | Mostly English instead of Tamil, or garbled |
| Understood Tamil-script / Tanglish requests (of 10) | **10** | 10 | ~6 |
| Tamil in help answers | Correct but generic ("you can use this") | Several wrong meanings (*"நானே உங்களை மன்னிக்க வேண்டும்"* = "I must forgive you") | Gibberish |
| Speed (Mac GPU) | 53–64 tok/s | 24–35 tok/s | 53–74 tok/s |

## Examples (Gemma 4 E2B)
- *Myself Karthik and I am having two years of experience in sales.* → *I am Karthik, and I have two years of experience in sales.* — "தன்னுடைய பெயரை சொல்லும்போது 'Myself' பயன்படுத்தக்கூடாது."
- *We discussed about the budget and he told that it is fine.* → *We discussed the budget, and he said it was fine.* — "discuss-க்கு 'about' தேவையில்லை."
- Interview: learner *"I am working in Infosys since 2021…"* → *"That sounds interesting. Could you describe the main technologies you used in that banking project?"*

## Gemma's weak spots (handle in the app)
- **Indian-English idioms are only half fixed:** it changed *revert back → revert*, but international business English uses *get back to me / reply*. Keep a **curated list of common Indian-English mistakes** in the lesson content, and don't rely on the model alone.
- **Tamil explanations are short and generic** in free-form help. Write the Tamil explanations for lessons by hand (or AI-draft and then review them); use the model for live chat only.
- It sometimes returns `corrected: ""` for a correct sentence; treat that as "no change" in code.

## Indian models checked (2026-11-09)

### Agaram 2.5B (Murai Labs, Oct 2026, Apache 2.0): tested, not a fit for the tutor
Tamil-first, trained from scratch; `agaram-2.5b-instruct` Q4_K_M 1.56 GB / Q8_0 2.69 GB; llama architecture (llama.rn supports its `qwen35` pre-tokenizer).
- **Best natural Tamil and Tanglish of every model tested** (*"Kavalai padathenga, interview nervous aagurathu normal thaan…"*)
- **But it cannot do the tutor's main job.** Asked to correct English, it **translates the sentence into Tamil** instead (in our test format and in its own recommended format: no system prompt, temperature 0). It never fixed *Myself*, *discussed about*, *since 2019* or *do the needful*
- Corrections returned invalid JSON in 6 of 16 cases; twice it copied the instructions back as the answer
- Role-play: drifted out of role, repeated the learner's mistaken sentences word for word, invented facts (*"Infosys … moved to TCS"*)
- "Make it professional" kept *"Hey … asap"*; when English wasn't stated explicitly, it answered in Tamil
- Possible later use: polishing the Tamil wording of lesson explanations on the Mac while writing content. Not inside the app

### Sarvam (Sarvam AI): not tested, none fits
| Model | Why not |
|---|---|
| Sarvam-1 (2B) | Text-completion base model only ("cannot be used directly as a chat model"); **non-commercial licence** |
| Sarvam-M (24B) | ~14 GB at 4-bit, too big for phones |
| Sarvam-30B (MoE, 2.4B active) | 19.6 GB at Q4_K_M; every expert must be stored and loaded |
| Sarvam-105B | Far too big |
| Sarvam-Translate (Gemma 3 4B fine-tune) | Translation only, not a tutor; GPL-3.0 licence |

## Caveats
- The scoring of Tamil quality is my own reading. **A native Tamil speaker should check the Tamil explanations** in the raw files before we rely on them.
- 18 test cases per run is a small sample; speeds are from a Mac, not a phone.
