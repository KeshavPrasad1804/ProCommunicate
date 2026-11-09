# ProCommunicate — Project Plan

A **native iPhone app (Swift + SwiftUI)** that teaches **English to Tamil speakers**, focused on **spoken, professional and business English**, through **structured lessons** plus an **on-device AI speaking partner**.
Android may follow later as a separate Kotlin app reusing the same course content and prompts. The course format keeps the learner's native language configurable, so other languages (for example Telugu, Malayalam or Hindi → English) can be added later.
Personal / learning project: keep it simple, ship small working pieces, and add to them.

**How the app teaches and the full feature list: [FEATURES.md](FEATURES.md).** This plan covers how to build it.

---

## 1. Product in one paragraph

A Tamil speaker takes a short placement quiz. Each day they do a 5–10 minute lesson: useful phrases and one grammar or style point (for example, *"I have been working here since 2019"*, not *"I am working here since 2019"*), with instructions and explanations in Tamil. They review older items that spaced repetition says are due, then have a short **AI role-play in English**: a job interview, a client call, a team meeting or office small talk. The AI points out mistakes gently, with explanations in Tamil. The learner can also ask for help in Tamil script or Tanglish (*"client kitta deadline extend panna email ezhudhi kudunga"*) and get ready-to-use professional English.

### Course tracks (priority order, set 2026-11-09; full unit outline in FEATURES.md §4)
| Priority | Track | Example units |
|---|---|---|
| **1** | **Meetings and client calls** | Daily stand-up, opening a call, status updates, explaining delays, clarifying, "I'll get back to you", disagreeing politely, negotiating deadlines, demos, escalations, closing |
| **2** | **Job interviews** | Tell me about yourself, current role, projects (STAR), technical explanations, conflict, strengths and weaknesses, salary and notice period |
| 3 | Everyday work English | Small talk, your manager, asking for leave, apologising (mixed into tracks 1–2) |
| 4 | Emails and messages | Requests, follow-ups, deadline extensions (later) |
| All | **Fix common mistakes** | *Myself…*, *I am having…*, *revert back*, *do the needful*, *today itself*, *discuss about*, *prepone*, *same page*, *little bit* |

## 2. The learning loop (what every screen serves)

```
Learn (new items) → Practise (exercises) → Feedback (instant) → Speak (AI role-play) → Review (SRS, later)
```

## 3. Features by version

### MVP (v0.1): "one lesson works end to end"
- [ ] One course: **Tamil → English**; app instructions available in Tamil and English
- [ ] Course map: Tracks → Units → Lessons
- [ ] Lesson player with 4 exercise types:
  - Multiple choice (pick the correct or most professional sentence)
  - Build the English sentence by tapping word tiles (from a Tamil prompt)
  - Listening (TTS plays an English sentence, learner picks or types it)
  - Fix the mistake (spot and correct a common Indian-English error)
- [ ] Instant right/wrong feedback; a lesson-complete screen
- [ ] Progress saved on the device

### v0.2: memory and habit
- [ ] Spaced repetition (FSRS or SM-2) per vocabulary item
- [ ] Daily "Review" session built from due items
- [ ] Streak, XP, daily goal, local reminder notification

### v0.3: AI speaking partner
- [ ] English role-play tied to each unit (HR interviewer, UK client, manager, colleague)
- [ ] Tutor speaks at the learner's level and reuses the unit's phrases
- [ ] Gentle corrections under each learner message, labelled grammar or style, explained in Tamil
- [ ] "Ask in Tamil" helper: type in Tamil script or Tanglish, get professional English to use
- [ ] Rewrite helper: casual message → professional message or email
- [ ] Voice mode: speech-to-text for input, TTS for the tutor's replies
- [ ] All AI runs **on the phone** from a GGUF model sized for that device: no Mac, no cloud (see 4a)

### v0.4: accounts and sync
- [ ] Sign-in (email / Apple / Google)
- [ ] Progress synced to the cloud, so it survives reinstall and works across devices
- [ ] Placement test

### Later / stretch
- Pronunciation scoring, speaking exercises inside lessons
- More exercise types (fill in the blank, sentence ordering, dictation)
- AI-assisted content generation for new languages
- Leaderboards, achievements

## 4. Tech stack (recommended)

| Layer | Choice | Why |
|---|---|---|
| App | **Native Swift 6 + SwiftUI, iPhone first** (decided 2026-11-09). Minimum iOS 26; your iPhone 15 runs iOS 27 | Call mode and recordings make this an audio-heavy app: full control of audio, memory and the Neural Engine on a 6 GB phone |
| Project setup | **XcodeGen** (`project.yml` in the repo generates the Xcode project), Swift Package Manager for libraries | The project can be created and changed from text files, not only by clicking in Xcode |
| Navigation | SwiftUI `NavigationStack` + `TabView` | Built in |
| Local storage | **SwiftData** (progress, spaced repetition, mistakes, sessions) + files for recordings and models | Works offline; everything stays on the phone |
| Backend | **Supabase** (Postgres + Auth), optional, only for v0.4 sync | The AI no longer needs a cloud backend |
| AI tutor | **GGUF model on the phone via llama.cpp** (official Swift package / `llama.xcframework`, Metal GPU). No server, no Mac, no cloud. See section 4a | Free, private, fully offline; the same engine tested on the Mac |
| Text-to-speech | `AVSpeechSynthesizer` (Indian, UK, US English; enhanced voices) | Built in, on-device |
| Speech-to-text | **WhisperKit** (Core ML Whisper on the Neural Engine), English model | Offline; streaming during the call; word timings for fluency numbers and recordings |
| Voice and recording | `AVAudioSession` (.playAndRecord, voice-chat mode) + `AVAudioEngine` with voice processing (echo cancellation), voice activity detection, AAC recording via `AVAudioFile` | Call-like practice; listen back to every answer |
| Content | JSON files in the repo at first, moved to the database later | Easy to edit and version |

## 4a. On-device AI design

**Rule:** every AI feature runs **inside the installed app on the phone**. The app makes no network calls for AI.

The app talks to the AI through one interface, so the model or engine can be swapped later:

```ts
interface TutorEngine {
  chat(messages: Msg[], opts: { scenario; level; targetLang; vocab: string[] }): AsyncIterable<string>;
  correct(learnerText: string, targetLang: string): Promise<Correction[]>;  // JSON output
}
```

**Engine:** **llama.cpp** called directly from Swift (its official Swift package / `llama.xcframework`). It memory-maps the `.gguf` file from the app's storage and runs it on the iPhone GPU with Metal. We set `lazy_mode`, mmap, context size and KV-cache type ourselves, with no wrapper in between.

### Model per device

At first launch the app reads the phone's RAM and picks a model size that fits:

**Chosen model: Gemma 4 E2B** (Google, April 2026, Apache 2.0), file `gemma-4-E2B-it-Q4_K_M.gguf` from `unsloth/gemma-4-E2B-it-GGUF` (3.11 GB), text only, **thinking off**. Chosen from a hands-on test on 2026-11-09 (below).

| Device tier | Example phones | AI tutor |
|---|---|---|
| **High** (8 GB+ RAM) | iPhone 15 Pro and newer, recent flagship Android | **Gemma 4 E2B Q4_K_M** with lazy embeddings: full role-play + corrections |
| **Mid** (6 GB) | iPhone 13/14, mid-range Android | **Same model**. With lazy embeddings it uses about 1.6 GB, so it should fit; confirm on a real phone in Phase 3a |
| **Low** (≤4 GB) | Older phones | **No AI tutor**: lessons, review and speech only. No small model tested well enough |

### Keeping memory low so the phone stays fast (measured 2026-11-09, `bench/measure_memory.py`)

Measured on the Mac after one reply. "Counted memory" (`phys_footprint`) is what iOS uses to decide when to kill an app. "In RAM" (RSS) is what the model actually takes from the phone.

| Build + settings | File | Counted memory | In RAM | Speed |
|---|---|---|---|---|
| Q4_K_M, settings used in the quality tests | 3.11 GB | 0.18 GB | 3.15 GB | 57 tok/s |
| Q4_K_M, phone settings | 3.11 GB | 0.12 GB | 3.12 GB | 49 tok/s |
| **Q4_K_M, phone settings + lazy embeddings** ✅ | 3.11 GB | **0.15 GB** | **1.61 GB** | **61 tok/s** |
| Q4_K_M, phone settings, CPU only | 3.11 GB | 1.39 GB | 4.36 GB | 18 tok/s |
| Q4_K_M, phone settings, no mmap | 3.11 GB | 3.48 GB | 3.57 GB | 50 tok/s |
| QAT UD-Q4_K_XL, phone settings + lazy embeddings | 2.62 GB | 0.12 GB | 1.43 GB | 66 tok/s |

*Phone settings* = 1 conversation slot, 2048-token context, KV cache in `q8_0`, flash attention on, GPU.

**What this means**
- **Lazy embeddings** (llama.cpp `lazy_mode = ON`) read Gemma's large per-layer embedding tables from storage only when a row is needed. **RAM drops by half (3.1 → 1.6 GB) with identical output** (checked at temperature 0) and no slowdown
- **Use mmap and the GPU.** With mmap, the weights are file-backed memory the OS can reclaim; without it the app itself holds 3.5 GB and is much more likely to be killed. CPU-only is 3× slower and uses more memory
- **Keep Q4_K_M, not the smaller QAT build.** QAT saves only 0.18 GB of RAM once lazy embeddings are on, but scored worse on Tamil → English corrections (missed *do the needful*, a Hindi word leaked into a Tamil explanation). It stays as a fallback if download size or storage matters more
- Load the model only on the Speak / Ask screens and unload it when the learner leaves, so lessons use almost no extra memory

**In the Swift app:** use a llama.cpp build that includes `lazy_mode` (the Homebrew build tested here, b12110, has it) and set `lazy_mode = LLAMA_LAZY_MODE_ON` in the model parameters. The default (`AUTO`) applies only to tensors over 4 GiB, which Gemma E2B's are not, so it must be set explicitly. Phase 3a starts by confirming these numbers on the iPhone 15.

### Tamil → English test (2026-11-09): Gemma 4 E2B confirmed, see [bench/TAMIL_RESULTS.md](bench/TAMIL_RESULTS.md)

| | Gemma 4 E2B ✅ | Qwen 3.5 4B | Qwen 3.5 2B |
|---|---|---|---|
| Indian-English mistakes fixed (of 9) | **8.5** | ~7 | ~6.5 |
| Tamil explanations | **Correct and clear** | Often wrong words or meanings | Mostly not in Tamil, or garbled |
| Understood Tamil-script / Tanglish requests | **10/10** | 10/10 | ~6/10 |
| Role-play English | Natural, short, stays in role | Natural but long | Invents facts |

What this means for the content: some Indian-English idioms are only half fixed (*revert back → revert* instead of *get back to me*), and Tamil explanations in free-form help are generic. So the **"common mistakes" list and the lesson explanations in Tamil are written as content** (AI-drafted, then checked by a Tamil speaker), and the model handles live chat and corrections only.

### First model test (2026-11-09): Spanish, French, Hindi, Japanese (script: `bench/run_bench.py`, raw output: `bench/results*/`)

Same prompts for every model, in 4 languages (Spanish, French, Hindi, Japanese), run twice:
- **Role-play:** the model is a café waiter talking to an A1 learner (2 turns per language)
- **Corrections:** a learner sentence with 3 planted mistakes, returned as JSON. Also a fully correct sentence, to catch invented mistakes

| Model | File | Role-play replies broken or out of role (of 16) | Planted mistakes fixed | Invented mistakes on correct sentences (of 8) | Speed on M5 Mac* |
|---|---|---|---|---|---|
| **Gemma 4 E2B Q4_K_M** ✅ | 3.11 GB | **2** | **~90%** | 1 harmless no-op entry | 53–64 tok/s |
| Qwen 3.5 4B Q4_K_M | 2.74 GB | 9 (kept asking the customer for prices) | ~80% (always missed Japanese 二つを and Hindi मैंने…खरीदे; one run broke the JSON) | 0 | 32–35 tok/s |
| Qwen 3.5 2B Q4_K_M | 1.28 GB | 6 (broken Hindi and Japanese) | ~40% (wrongly called "La agua" correct; never caught मेरी भाई) | 2 | 60–74 tok/s |
| Gemma 4 E2B "mobile" QAT Q2 | 2.19 GB | 3 | Vague; explanations were useless | 4 of 4 | 72–82 tok/s |

\*Mac GPU speeds are only useful for comparing the models with each other. Phones will be several times slower; measure on a real phone in Phase 3a.

**Why Gemma 4 E2B won**
- Most natural replies: it stayed in the waiter role, kept replies short, and ended with a question (for example *"Un café et un croissant, c'est quatre euros. Voulez-vous autre chose ?"*)
- Most accurate corrections, with short, clear explanations
- Faster than Qwen 4B even though its file is bigger. Only ~2B parameters do the work for each token
- Bonus for later: it understands speech by itself, so it might replace Whisper (not tested yet)

**Rejected:** Agaram 2.5B (best Tamil, but translates English into Tamil instead of correcting it; see bench/TAMIL_RESULTS.md); Sarvam-1 (base model only, non-commercial licence); Sarvam-M / 30B / 105B (14–60+ GB, too big for phones); Sarvam-Translate (translation only, GPL); Qwen 3.5 4B (slower, weaker in role and in Japanese/Hindi); Qwen 3.5 2B and 0.8B (not good enough for teaching); Gemma 4 mobile Q2 (unreliable corrections); Gemma 4 E4B (5.2 GB, too big for phones); Qwen 3.6 (no small sizes).

**What the app must do with this model** (lessons from the test)
- Run with thinking **off** (`--reasoning off` / `enable_thinking: false`). Once, Gemma started hidden "thinking" anyway and used up its whole reply length
- Corrections must use a **JSON schema with a length cap on explanations**. Without the cap, Qwen 4B once rambled until the reply was cut off
- **Clean up the corrections in code:** drop entries where `wrong == right`, and treat an empty `corrected` as "no change"
- Prompts must state the role plainly (*"YOU are the waiter… never ask the customer what something costs"*). This cut out-of-role replies sharply
- Show corrections as **suggestions**, not as final answers. Even the best model gets about 1 in 10 wrong, especially in Hindi and Japanese
- Note: Hindi "कल" means both *yesterday* and *tomorrow*, so test sentences must avoid ambiguous words like it

### How the model gets onto the phone

| Option | How | Pros | Cons |
|---|---|---|---|
| **Download once on first launch** (recommended) | App downloads the right GGUF for the device tier into its private storage, with a progress bar and resume | Small app install; no Mac needed; model survives app updates | Needs Wi-Fi once |
| **Bundled in the installer** | GGUF ships inside the `.apk` / `.ipa` | Works with zero network from the first launch | Installer is 1–2.5 GB larger; every rebuild/reinstall during development is slow; one model for every device |

After it is on the phone, everything runs offline. A "Manage AI model" screen shows the model, its size, and buttons to delete or re-download it.

### Mock interview mode: context, memory and feedback (tested 2026-11-09)

A full mock interview (20–30 min, 15–25 questions, long spoken answers) is the most demanding feature. Measured on the Mac with `bench/measure_context.py` and `bench/interview_feedback_test.py`:

**1. Context size: use 8192 for interview mode.** One exchange with a spoken-length answer (60–80 words) uses about **130 tokens**, so a 20-question interview is about 2.6k tokens plus a 250-token setup. 8192 holds about 60 exchanges.

| Context (filled) | Exchanges | Counted memory | In RAM | Generation | Time to read the whole transcript |
|---|---|---|---|---|---|
| 2048 (1.7k) | 13 | 0.19 GB | 1.66 GB | 60 tok/s | 1.0 s |
| 4096 (3.5k) | 29 | 0.22 GB | 1.69 GB | 57 tok/s | 1.2 s |
| **8192 (7.3k)** | 63 | 0.24 GB | 1.72 GB | 51 tok/s | 2.3 s |
| 16384 (14.5k) | 127 | 0.29 GB | 1.76 GB | 43 tok/s | 4.3 s |

Memory barely grows (Gemma 4 keeps most of its attention in a small sliding window). The real cost of a very long context is **speed**: replies slow down as it fills, and re-reading the whole transcript (for example after the app was in the background) takes seconds on the Mac and several times longer on a phone. During a live conversation, only the new turn is processed.

**2. A long memory alone does NOT give good feedback.** With the whole 7k-token interview in context, the end-of-interview feedback was **generic and partly made up**: it mentioned "pauses" and "pronunciation" it could not know, and missed every real mistake (*Myself Priya*, *I am working since 2021*, *I am having*, *told it is a bug*, *in the same page*).

**3. What works: check each answer as it comes in, save the mistakes, build the report from them.**
- Each answer is checked by a separate correction call. It caught *Myself Priya Ramesh → I am Priya Ramesh*, *from then I am working → since then I have been working*, *I am having → I have*, *told it is a bug → said it was a bug*, *in the same page → on the same page*, *little bit nervous*, with Tamil explanations
- Mistakes are saved in SQLite. The final report is generated **from that list** (3–8 s on the Mac), so it quotes the learner's own words
- Still to improve: some nitpicks (*handled → managed*, *one and half seconds → 1.5 seconds*); the report listed 15 items instead of the top 3, so the app should pick and rank them in code

**4. Speed of the per-answer check:** about **15 s per 70-word answer on the Mac** (~700–800 tokens out, mostly Tamil explanations and JSON), so likely **45–60 s on a phone**. Design around it:
- **Never block the conversation.** The interviewer's next question is generated first (~40 tokens, a few seconds), and the check runs **in the background while the learner speaks the next answer** (which takes 30–60 s anyway). The model is idle during recording; Whisper runs after recording stops
- **Catch the common Indian-English patterns instantly with rules**, with hand-written Tamil explanations (*Myself…*, *I am having…*, *revert back*, *do the needful*, *today itself*, *discuss about*, *since + "I am working"*, *in the same page*, *little bit*, *cousin brother*, *prepone*). The model handles everything else
- **Generate the Tamil explanation only when the learner taps a mistake**, which cuts the background check's output by more than half
- **Pin "interview notes"** (name, company, projects, numbers the candidate mentioned) in the system prompt, so that if an unusually long interview has to drop old turns, the interviewer still remembers the key facts
- Save the KV cache with llama.cpp's state-save functions (`llama_state_save_file`) when the app goes to the background, so returning to an interview doesn't re-read the whole transcript

### Speech, also on the phone
- **Speech-to-text:** Whisper on the phone. **WhisperKit** (Core ML, runs on the Neural Engine and leaves the GPU free for Gemma). Use an English model (`base.en` or `small.en`), since learners answer in English; *Ask in Tamil* is typed
- **Text-to-speech:** the phone's built-in voices (Indian, UK, US English; the "enhanced" voices sound much better). A small on-device neural voice can come later if the built-in ones sound too robotic

### Call mode: the voice pipeline (meetings, interviews, role-plays)

The core of the app is a **voice conversation that feels like a real phone or Teams call**, with everything recorded. See FEATURES.md "Call mode" and "Recordings".

```
mic ──► echo cancellation ──► voice activity detection ──► Whisper (streaming, while you talk)
 │                                   │ end of your turn (~0.7 s pause)          │ transcript + word timings
 │                                   ▼                                           ▼
 │                       instant "Mm-hmm / Okay" clip                Gemma: interviewer/client reply
 │                                                                                │ streamed sentence by sentence
 ▼                                                                                ▼
recorder (your voice + AI voice, AAC) ◄──────────────────────────────── text-to-speech (speaks as soon as
                                                                          the first sentence is ready)
background (while you speak next):  answer check → saved mistakes → report at the end
```

**Response-time target:** the other person starts replying **within about 2–3 seconds** after you stop.
| Step | Budget (iPhone 15, estimated) |
|---|---|
| Detect that you've finished (pause) | ~0.7 s |
| Finish the transcript (most of it is done while you talk) | ~0.3–1 s |
| Gemma reads your answer + writes its first sentence (~15 tokens at ~12–18 tok/s) | ~1–1.5 s |
| Text-to-speech starts | ~0.2 s |
| An "Mm-hmm" clip plays instantly to cover the gap | 0 s |

**Building blocks:**
- **Audio session in voice-chat mode** with the system's echo cancellation and noise reduction, so the AI's voice through the speaker isn't transcribed as yours. Works with earphones and AirPods
- **Voice activity detection** (a small model such as Silero VAD) for end-of-turn detection and for **interrupting the AI** (you start talking → its speech stops)
- **Recording:** both sides go into one AAC file per session (~1 MB/min; a 25-minute interview is ~25 MB), plus each of your answers as a separate clip. Word timings from Whisper link the transcript, mistakes and fluency numbers to exact moments
- **Fluency numbers from the timings:** words per minute, pauses over 2 s, fillers (*umm*, *actually*, *basically*, *like*)
- **Phone-line sound (optional):** filter the AI's voice to the 300–3400 Hz telephone band and add light line noise
- **Memory: Whisper and Gemma loaded together during a call** (~0.2–0.5 GB + ~1.6 GB). Whisper runs on the Neural Engine and Gemma on the GPU, so they don't fight over the same chip. **Must be measured on the iPhone 15** (Phase 3a)
- **Background answer checks** run on the GPU while you're speaking the next answer (Gemma is idle then); the call itself always takes priority
- **Surprise call (later):** a time-sensitive local notification that opens straight into call mode. (A real incoming-call screen through CallKit needs a push server, so it isn't planned)
- **Limits to be clear about:** iPhone apps can't record phone calls. *Analyse my recording* works on audio files you import (your own voice, or meetings everyone agreed to record). On-device speaker separation is a later experiment

**Tests to run before building call mode (Phase 3a, on the iPhone 15):**
1. Whisper `base.en` vs `small.en` on **Tamil-accented English**: does it write down exactly what you said, including mistakes like *"I am having"*, or does it quietly "fix" your grammar? (This decides whether the corrections can be trusted)
2. End-to-end reply time in a 10-minute call
3. Memory with Whisper + Gemma + recording running together; no app kills over a 25-minute session
4. Heat and battery drain over a 25-minute call

### Device limits to plan for
- **Memory:** iOS may close an app that uses too much RAM. Use mmap + GPU + lazy embeddings (see "Keeping memory low" above), a `q8_0` KV cache, 2048–4096 tokens for short role-plays and 8192 for mock interviews, and add the *Increased Memory Limit* entitlement as a safety margin
- **Speed:** a 3–4B model on a recent phone runs at roughly 10–20 tokens per second, which is fine for 1–2 sentence replies. Stream tokens to the screen as they arrive
- **Heat and battery:** unload the model when the Speak tab closes
- **First-load time:** loading the model takes a few seconds, so preload it when the user opens the Speak tab

### Getting good results from small models
- Short system prompts with the scenario, the learner's CEFR level, and the unit's word list
- Ask for short replies (1–2 sentences) and a slow, simple register for beginners
- Corrections come from a **separate call** whose output is forced into JSON by a **llama.cpp grammar**, so they don't interfere with the conversation
- Lower temperature for corrections, higher for conversation
- Keep only the last N turns in context so it stays fast and fits in memory

### Your test phones
| | iPhone 15 | iQOO Neo 10 |
|---|---|---|
| Chip / GPU | A16 Bionic, Apple GPU (Metal) | Snapdragon 8s Gen 4, Adreno 825 (OpenCL) |
| RAM | 6 GB (the "mid" tier) | 8 / 12 / 16 GB LPDDR5X |
| Model file | `gemma-4-E2B-it-Q4_K_M.gguf` | Probably a **Q4_0** build (Google's official QAT `q4_0`, 3.35 GB, or unsloth `Q4_0`, 3.04 GB): llama.cpp's Adreno GPU backend is optimized for Q4_0 only. Otherwise fall back to CPU with Q4_K_M |
| Expected speed (estimate, not measured) | ~12–18 tok/s, so a 2-sentence reply takes ~2–4 s | GPU path unknown (Adreno 825 is not on llama.cpp's verified list); CPU ~10–15 tok/s |
| Your device | iPhone 15 (base), **iOS 27.0.1**, 128 GB with **15.7 GB free** (checked 2026-11-09). Needs ~3.5 GB for Gemma + Whisper + app. Base iPhone 15 has no Apple Intelligence, so Gemma is the only on-device AI option | — |
| Main risk | iOS memory limit on a 6 GB phone: needs mmap + Metal + lazy embeddings, and run Whisper and Gemma one after the other, not together | Q4_0 quality not yet tested on Tamil → English; GPU driver support |

Before building screens around the AI, confirm speed and memory on the iPhone (start of Phase 3a, or earlier with PocketPal AI, an existing app that loads GGUF files and shows tokens/s). The iQOO column applies only if an Android app is built later.

### Building and installing on your iPhone (Xcode isn't installed on this Mac yet)
- Install the **latest Xcode** from the Mac App Store (it must support iOS 27), then `xcode-select -s /Applications/Xcode.app`, and add the iOS platform when Xcode asks
- Connect the iPhone by cable once, turn on **Developer Mode** (Settings → Privacy & Security), and sign the app with your Apple ID in Xcode
- **Free Apple ID:** the app runs for 7 days, then needs reinstalling from Xcode. **Paid Apple Developer account ($99/year):** 1-year installs and TestFlight. Some capabilities (for example *Increased Memory Limit*) may need the paid account; check when we add it
- Builds and tests run from the command line with `xcodebuild`; the iOS Simulator is for screens, but AI speed, memory, microphone and Neural Engine work must be checked on the real iPhone

## 5. Content model (language-agnostic)

Content is JSON in the repo, decoded into Swift `Codable` structs (shared with a future Android app). Shown in TypeScript-style notation for brevity:

```ts
Course   { id, targetLang: "en", sourceLang: "ta", title, tracks[] }       // Tamil → English
Track    { id, title /* Spoken | Professional | Business */, units[] }
Unit     { id, title, description, scenario /* AI role-play: role, setting */, lessons[] }
Lesson   { id, title, newItems: ItemId[], exercises: Exercise[] }
Item     { id, text /* English */, translation /* Tamil */, register?: "casual" | "professional",
           commonMistake?: { wrong, explanationTa }, audio?, example? }      // phrase or sentence
Exercise { id, type: "mcq" | "tiles" | "listen" | "fix", prompt, answer, options?, itemIds[] }
```

Learner data:

```ts
ItemProgress   { itemId, stability, difficulty, due, reps, lapses, lastReviewed }  // SRS state
LessonProgress { lessonId, completedAt, score }
Profile        { streak, xp, dailyGoal, activeCourse }
Conversation   { id, unitId, kind /* roleplay | meeting | interview */, messages[], recordingFile, createdAt }
Mistake        { id, sessionId, wrong, right, type, explanationTa?, audioStart, audioEnd, pattern, createdAt }
```

Learner data is stored with SwiftData on the phone.

Supporting many languages comes down to: every string the learner sees in the target language lives in content files keyed by `targetLang`, and the UI itself is translated separately (i18n).

## 6. Proposed folder structure

```
ProCommunicate/
  project.yml                  # XcodeGen project definition
  ProCommunicate/              # the iOS app
    App/                       # app entry, tabs, settings
    Features/
      Learn/                   # course map, lesson player, exercises (MCQ, tiles, listen, fix)
      Review/                  # spaced-repetition review, by speaking
      Call/                    # call mode: meeting simulation, mock interview, role-plays
      Reports/                 # session reports, recordings player, My Mistakes
      AskTamil/                # Tamil / Tanglish helper
    Core/
      AI/                      # LlamaEngine (llama.cpp), TutorEngine, prompts, JSON schemas
      Speech/                  # WhisperKit STT, VAD, text-to-speech, audio session
      Recording/               # AAC recorder, clip index, storage cleanup
      Learning/                # SRS (FSRS), mistake patterns (rules), fluency metrics
      Data/                    # SwiftData models, content loader
    Resources/
      content/ta-en/           # Tamil → English course JSON (shared with a future Android app)
  ProCommunicateTests/         # unit tests (SRS, mistake rules, content decoding, prompts)
  bench/                       # model tests on the Mac (done)
```

## 7. Build phases

| Phase | Outcome | Rough effort |
|---|---|---|
| 0. Setup ✅ (2026-11-09) | Xcode installed; SwiftUI app generated with XcodeGen, running on your iPhone 15 with tabs and navigation; unit tests running with `xcodebuild` | 1 day |
| 1. Lesson engine ✅ (2026-11-09) | One sample unit ("Giving a status update on a client call") is playable end to end with 4 exercise types | 2–4 days |
| 2. Progress + SRS | Review tab works; streak and XP | 2–3 days |
| 3a. On-device AI engine | llama.cpp running Gemma 4 E2B on the iPhone (Metal, mmap, lazy embeddings); measure speed, memory and heat; model download and manage screen | 3–4 days |
| 3b. Voice and call mode | WhisperKit + voice activity detection + echo cancellation + text-to-speech + recording; run the 4 call-mode tests; then short call-mode role-plays with corrections | 4–6 days |
| 4. Accounts + sync | Sign-in, cloud progress | 2–3 days |
| 5. Content + polish | All 3 tracks filled, placement test, animations, sounds; later more native languages → English | ongoing |

## 8. Open decisions (to settle before or during Phase 0)
1. ~~Which languages~~ → decided: **Tamil → English** (spoken, professional, business); more native languages later
2. Where content comes from: recommended **AI-drafted, then checked by a Tamil speaker** (especially the Tamil explanations)
3. App name, visual style, and colour scheme
4. ~~Paid AI budget~~ → decided: **on-device GGUF models only**, running inside the installed app. No Mac server, no cloud
5. ~~Which GGUF model~~ → chosen after hands-on tests: **Gemma 4 E2B Q4_K_M** on 8 GB+ phones; still to test whether it fits on 6 GB phones (Phase 3a); no AI tutor on ≤4 GB phones
6. Model delivery: download on first launch (recommended) or bundle it in the installer
7. ~~Which phone first~~ → decided: **iPhone 15**
8. ~~App framework~~ → decided: **native Swift + SwiftUI, iPhone first** (call mode and recordings need full audio and memory control); Android later as a separate Kotlin app sharing the content JSON and prompts
9. Apple Developer account: free Apple ID (7-day installs) to start, or paid ($99/year) for longer installs and possibly the *Increased Memory Limit* capability
