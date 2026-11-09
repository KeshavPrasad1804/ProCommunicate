# Can the app understand spoken Tamil and Hindi? (2026-11-09)

Script: `bench/run_listen_test.py` · Raw output: `bench/results-listen/synthetic.json`
Clips: `bench/audio/synthetic/` (made with macOS voices: Vani for Tamil, Lekha for Hindi, Rishi and Aman for Indian English). Real-voice clips go in `bench/audio/mine/` (**still to do**).

The app's tutor needs a learner to be able to say, mid-call or mid-lesson: *"இதை English-ல எப்படி சொல்றது? project ஒரு வாரம் delay ஆகும்"* and get back the English line to say.

## Results (8 Tamil/Hindi clips + 2 Indian-English clips, Mac M5)

| | Whisper small, multilingual (488 MB) | Gemma 4 E2B listening (our model + audio encoder) |
|---|---|---|
| **Indian English, word for word** ("revert back", "I am having") | ✅ 2/2 | ✅ 2/2 |
| **Transcribing Tamil / Hindi script speech** | English words inside come out garbled (*client → க்லாயன்*, *project → பிராய்க்கூர*) | Better: *கிளient கிட்ட … extend பண்ணணும்னு*. It sometimes drops a word ("project") |
| **Transcribing Tanglish / Hinglish** | ❌ broken (*"Inaku and her question Puriya La"*); one clip got stuck repeating "च्च्च्" | ✅ *"Sorry, enakku andha question puriyala. Konjam explain pannunga."* and *"client se deadline badhane ke liye kaise poochu"* were perfect |
| **Its own translation to English** | Gets the gist for script clips; fails on mixed speech | — |
| **One step: listen and work out the meaning** | — | ❌ It made things up (*"the acronym NAAY"*) |
| **Two steps: transcript first, then Gemma works out the meaning** | ~1.5 of 8 right | **6.5 of 8 right** |
| **Speed per clip** (Mac) | ~0.45 s | ~0.5 s transcribe + ~0.7 s meaning |

The one clip both failed (ta3) is an *English* voice reading Tanglish, which isn't how a person sounds. **Real recordings are the real test.**

## What it means for the app
- **Use Gemma to listen, in two steps:** first transcribe exactly, then ask Gemma (text) what the learner meant and what they should say. Gemma's text understanding of Tamil, Tanglish, Hindi and Hinglish was already strong (`TAMIL_RESULTS.md`, `HINDI_RESULTS.md`).
- **Whisper multilingual isn't worth adding.** It's worse at exactly the mixed speech learners use.
- **Gemma might replace Whisper for English answers too** (2 of 2 word for word here). That would leave one model on the phone instead of two. Needs testing on real accented English.
- **Memory:** the encoder file is 986 MB, but only **612 MB is audio** (366 MB is the image part, which the app doesn't need). An audio-only file, possibly quantised, could be ~300–600 MB on top of Gemma.
  - If Gemma replaces Whisper, the speech model's ~217 MB (and its 146 s first-launch preparation) goes away.
- **Unknowns for the iPhone:**
  - llama.cpp marks audio input as "experimental".
  - Speed on the phone's GPU.
  - Memory with Gemma and the audio encoder loaded together on 6 GB.
  - Whether the vendored llama.cpp b12211 build includes Gemma 4 audio. Its headers include the multimodal library (`mtmd.h`, with audio support).

## On the iPhone 15 (2026-11-09)
Setup: the audio-only encoder (`tools/strip_mmproj.py`, 619 MB) was copied to the phone, and all 10 clips were run with `-runListenTest YES`. The report is written to `Library/Caches/listen-test.txt`.

| | iPhone 15 |
|---|---|
| Gemma load | 2.4 s |
| Listening part load | 1.2–2.5 s |
| App memory: Gemma only → with listening | 263 MB → 895 MB (**+630 MB**) |
| App memory while listening | ~945 MB, with **2.27 GB still free** before iOS would close the app |
| Hearing a 3–5 s clip | **2.0–2.6 s** (4.6 s once) |
| Working out the meaning | **2.2–3.1 s** |
| A help request in total | **~4.5–5.5 s** |

**Quality matched the Mac:**
- **English:** "revert back" and "I am having" were heard word for word.
- **Tamil and Hindi requests** were understood: *"How should I ask the client if we can get a deadline extension?"*
- **Tanglish and Hinglish "please explain"** were understood.
- **The synthetic ta3 clip failed again** (an English voice reading Tanglish).

**Verdict:** Gemma listening is fast enough and fits in memory for a **Help button** and a **bilingual tutor**. About 5 seconds is fine for "how do I say this?", but too slow to replace Whisper for every call turn without more testing.

**Still open:**
- **Getting the 619 MB listening file onto users' phones.** Either download unsloth's 986 MB mmproj from the pinned commit and strip it on the phone, or host the stripped file.
- **Memory during a full call**, with Whisper and Gemma's listening part both loaded.
- **Real accented voices.**

## Next
1. ~~Audio-only encoder, measured on the iPhone~~ (done above).
2. **Build the tutor features:** a Help button in calls, a bilingual tutor session, and spoken explanations in Tamil or Hindi (iOS voices Vani and Lekha).
3. **Delivery:** let the app download and prepare the listening file itself.
4. **Real voices:** you can test any time in Settings → AI test lab → "Speak", or by putting clips in Files → ProCommunicate → ListenTest.
