# Hindi content: to review (2026-11-09)

The Hindi pack (`ProCommunicate/Resources/content/hi-en/`) is built from:
- `tools/translations/hi/meetings.json` and `interviews.json`: 330 lesson lines
- `tools/translations/hi/rules.json`: 21 mistake explanations

After editing a translation, rebuild and check:
```
python3 tools/build_language_pack.py hi && python3 tools/validate_lessons.py
```
All of it is AI-drafted, so **a native Hindi speaker should check it**. It is everyday office Hindi in Devanagari, with English work words kept in English (stand-up, PR, deadline, client…). Every lesson is marked `nativeReviewed: false`.

## Decisions to make
1. **Gender of "I" sentences.** Hindi verbs change with the speaker's gender; Tamil verbs don't.
   - The **interview** lessons use gender-neutral wording where it reads naturally, and masculine elsewhere: 02 working-since, team-of-eight, code-reviews; 06 working-on, to-improve; 10 in-that-situation, prioritise (and their build prompts).
   - The **meetings** lessons use masculine throughout: करूँगा, करता हूँ, समझता हूँ…
   - The options: keep masculine, rewrite these lines neutrally, or add a "your gender" setting and a feminine variant of each line.
2. **Weekdays and names.** These follow the Tamil: weekdays are in Hindi (शुक्रवार, सोमवार) and names are in Devanagari (प्रिया). Many people say "Friday" in English.
3. **Place names in the English lessons** are shared with Tamil (Chennai, Anna University, Madurai), so the Hindi meanings keep them. The role-play scenarios use Pune instead of Chennai.

## Lines to check
- **Answer held back on purpose.** These Hindi lines avoid giving away the English answer in review:
  - "Unfortunately" → अफ़सोस की बात है कि
  - "Could you clarify" → थोड़ा समझा सकते हैं
  - "get back to you" → आपको जवाब देता हूँ
  - "off the top of my head" → अभी इस वक़्त मैं पक्का नहीं कह सकता (a loose rendering)
- **"To summarise"** → संक्षेप में. It is slightly formal; the alternative is "Short में कहूँ तो".
- **Reworded to avoid gender:**
  - interviews-01 currently-work: "फ़िलहाल मेरा काम … पर है"
  - interviews-01 next-step: "अब मेरा goal है … grow करना"
  - interviews-10 havent-worked: "मेरा approach होगा …"
- **Possibly a little formal:** interviews-04 walk-through: "मुझे आपको architecture step by step समझाने दीजिए।"
- **Mistake notes:** `tools/translations/hi/rules.json`, all 21.
- **Fixed lines in the app:** "आपने क्या सुना?", "सही sentence चुनिए।", "हिंदी में", and the stand-up prompts in `Core/Data/NativeLanguage.swift`.

## AI-written Hindi
The AI's Hindi was tested on the Mac (`bench/HINDI_RESULTS.md`). It is correct but tends to be formal, so the prompts ask for everyday office Hindi.
