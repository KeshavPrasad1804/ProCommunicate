# ProCommunicate

A native iPhone app that teaches **Tamil and Hindi speakers to speak professional English at work**, mainly in **client meetings** and **job interviews**. It does this with short lessons, spaced review and **practice calls with an AI that runs entirely on the iPhone**. Nothing you say leaves the phone.

> Personal project, in active development. It runs on an iPhone 15; the Tamil and Hindi content is AI-drafted and still needs native-speaker review.

## What it does

- **A 20-minute day:**
  - a stand-up drill (your real yesterday / today / blockers update)
  - a warm-up review
  - a lesson
  - a short practice call
  - today's fix for your most repeated mistake
- **Practice calls that feel like real phone or Teams calls.** You speak and the AI answers by voice: a UK client, an HR interviewer, a sprint demo. After the call you get a report with your top fixes, playback of your own voice and your words-per-minute. Answers are checked in the background and you get a notification when the report is ready.
- **Two tracks:**
  - **Meetings and client calls:** 12 units, from the stand-up to closing a meeting.
  - **Job interviews:** 10 units, from "Tell me about yourself" to the HR round.
- **Catches Indian-English habits:** *Myself…*, *I am having…*, *revert back*, *do the needful*, *today itself*, *prepone* and 15 more. Each is explained in your language.
- **Adapts to you:**
  - A learner model scores every unit from your lesson results, review memory and call mistakes, and lets the score fade over time.
  - Today's plan picks the unit that fixes a mistake you keep making, or one that has faded, or the next new skill. Each step says why it was chosen.
  - The weekly challenge call gets harder as your mistakes drop.
- **Written for your job.** When the phone is idle, the on-device AI writes a daily phrase and a weekly challenge call around your role and project.
- **Meeting prep:** describe tomorrow's meeting in English, Tamil, Tanglish, Hindi or Hinglish. You get a cheat sheet of phrases and a rehearsal call, and on the day before, your daily call becomes that rehearsal.
- **Ask in your language:** type in Tamil or Hindi (script or romanised) and get ready-to-use professional English.
- **Spaced review (FSRS)** of every phrase you learn and every mistake you make.

## How it works

| Part | Technology |
|---|---|
| App | Swift 6, SwiftUI, SwiftData. iOS 26 or later; iPhone with 6 GB+ RAM for the AI tutor |
| AI tutor | **Gemma 4 E2B** (Q4_K_M GGUF, 3.1 GB) via [llama.cpp](https://github.com/ggml-org/llama.cpp) on Metal, with lazy embeddings (about 1.6 GB of memory). Grammar-constrained JSON for answer checks |
| Speech → text | [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (`whisper-small.en`) on the Neural Engine |
| Listening in Tamil / Hindi (experimental) | Gemma 4's own audio encoder. It handles Tanglish and Hinglish well; see [bench/LISTEN_RESULTS.md](bench/LISTEN_RESULTS.md) |
| Text → speech | iOS voices: Indian, British or American English |
| Course content | JSON per language in `ProCommunicate/Resources/content/<lang>-en/`. The English side is shared; translations live in `tools/translations/` |

The model was chosen after tests on the Mac in Spanish, French, Hindi, Japanese and Tamil; see [PLAN.md](PLAN.md) and [bench/](bench/).

## Build and run

You need macOS with **Xcode 27** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Download the llama.cpp library (its checksum is verified):
   ```bash
   sh tools/fetch-llama.sh
   ```
2. In `project.yml`, set `DEVELOPMENT_TEAM` to your own Apple team ID.
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Open `ProCommunicate.xcodeproj` and run on an **iPhone**. The AI engine is device-only; in the Simulator, everything except the AI runs.
5. In the app, open **Settings → AI tutor → Download**. This fetches the Gemma model (3.1 GB, from a pinned Hugging Face commit, checksum verified) and the speech model.

Run the tests:
```bash
xcodebuild test -project ProCommunicate.xcodeproj -scheme ProCommunicate -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Validate the lesson content, and rebuild a language pack after editing translations:
```bash
python3 tools/validate_lessons.py
```
```bash
python3 tools/build_language_pack.py hi
```

**Debug launch arguments** (for screenshots and testing):
- `-skipSplash YES`
- `-skipOnboarding YES`
- `-seedDemoData YES`
- `-openLesson <unitId>`
- `-startCall <scenarioId>`
- `-runListenTest YES`

## Project layout

```
ProCommunicate/
  App/            app entry, navigation, settings keys
  Core/AI/        llama.cpp engine, prompts, model download, Gemma listening
  Core/Adaptive/  learner model, adaptive planner, AI content jobs
  Core/Call/      practice calls, scenarios, background report checks
  Core/Speech/    microphone + turn detection, Whisper, text-to-speech
  Core/Learning/  FSRS review, lessons, mistake rules
  Features/       SwiftUI screens (Today, Learn, Practice, Review, Progress, Settings…)
  Resources/content/ta-en, hi-en   course, lessons, scenarios, mistake notes
ProCommunicateTests/   101 tests (Swift Testing)
bench/          model tests on the Mac (scripts + results)
tools/          content validator, language-pack builder, llama.cpp fetcher, mmproj stripper
```

## Documents

- [FEATURES.md](FEATURES.md): how the app teaches, and the full feature list and lesson outline
- [PLAN.md](PLAN.md): architecture, model choice, decisions and status
- [TESTING.md](TESTING.md): the on-device test checklist
- [TAMIL_REVIEW.md](TAMIL_REVIEW.md) · [HINDI_REVIEW.md](HINDI_REVIEW.md): content waiting for native review

## Licence

[MIT](LICENSE). The Gemma model is downloaded separately and is covered by its own licence.
