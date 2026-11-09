# Tamil to review

All Tamil in the app was drafted by AI and needs a native speaker's check. Every lesson file has `"tamilReviewed": false` until you've checked it. Tell me what to change (or edit the JSON directly).

## Where the Tamil is
- **22 lessons**: `ProCommunicate/Resources/content/ta-en/lessons/*.json`: `introTamil`, each phrase's `tamil`, `promptTamil`, `explanationTamil`
- **21 mistake rules**: `ProCommunicate/Core/Learning/MistakeRules.swift`: `whyTamil` (shown after calls and drills)
- **Screens**: stand-up drill prompts, speaking check, onboarding, the "Fix the mistake" and "Listen" headings

## Check these first (the writers were least sure)

### Meetings lessons
1. 01 stand-up, *blocked-on*: "API key-கள் இல்லாததால் என் வேலை நின்றிருக்கிறது; DevOps team-இன் உதவி தேவை." ("missing" was added for clarity)
2. 04 delay, *root-cause*: "மூல காரணம், third-party API-இல் எங்களுக்குத் தெரிவிக்காமல் செய்யப்பட்ட ஒரு மாற்றம்."
3. 05 clarify, *repeat-that*: "…உங்கள் குரல் கொஞ்சம் கட் ஆனது." Is "கட் ஆனது" natural for "you broke up"?
4. 06 get-back, *get-back-by*: "சரிபார்த்து, நாளை மாலைக்குள் உங்களுக்குப் பதில் சொல்கிறேன்." (for "by end of day tomorrow")
5. 06 get-back, *off-the-top*: "இப்போது உடனே உறுதியாகச் சொல்ல முடியவில்லை." (loose idiom)
6. 07 disagree, *completely-agree*: "…உங்களுடன் முழுமையாக ஒத்துப்போகிறேன்." or உடன்படுகிறேன்?
7. 08 interrupt, *add-something*: "இங்கே நான் ஒன்று சேர்க்கலாமா? இதை நாங்கள் கடந்த sprint-இல் test செய்தோம்."
8. 11 escalation, *heres-what*: "இதைச் சரிசெய்ய நாங்கள் என்ன செய்கிறோம் என்று சொல்கிறேன்."
9. 11 escalation, *take-ownership*: "இது எங்கள் தவறுதான்; முழுப் பொறுப்பையும் ஏற்றுக்கொள்கிறோம்." (stronger than "this is on us")
10. 12 closing, intro: "…மரியாதையான விடைபெறுதலுடன் முடியுங்கள்." Too literary?

### Interview lessons
11. 01 about-you, *java-dev*: "Backend services உருவாக்குவதில் மூன்று வருட experience உள்ள Java developer நான்." (word order)
12. 03 STAR, *challenge-was*: "எங்கள் loan approval API பதில் தர எட்டு வினாடிகள் எடுத்தது; அதுதான் சவால்."
13. 04 technical, *we-chose*: "ஒரு நாளைக்குச் சுமார் பத்து லட்சம் events-ஐ process செய்ய வேண்டியிருந்ததால் Kafka-வைத் தேர்ந்தெடுத்தோம்."
14. 04 technical, *trade-off*: "Complexity கொஞ்சம் அதிகமானது, ஆனால் scalability நன்றாக மேம்பட்டது; அதுதான் trade-off."
15. 06 strengths, *working-on*: "Senior stakeholders முன் present செய்வதை இப்போது மேம்படுத்திக்கொண்டிருக்கிறேன்." (long or stiff?)
16. 07 why, *what-attracts*: "Digital banking products-இல் நீங்கள் காட்டும் கவனம்தான் உங்கள் company-இடம் என்னை ஈர்க்கிறது."
17. 08 salary, *notice-period*: "என் notice period 60 நாட்கள்; பேசிக் குறைக்க முடியும்." (for "negotiable")
18. 08 salary, *expected-ctc*: "என் expected CTC 13 லட்சம், ஆனால் இதைப் பற்றிப் பேசத் தயார்."
19. 09 questions, *success-look*: "இந்த role-இல் முதல் ஆறு மாதங்களில் எதை வெற்றியாகப் பார்ப்பீர்கள்?"
20. 10 HR round, *relocating*: "ஆம், இந்த role-க்காக Bengaluru-க்கு இடம் மாற எனக்குச் சம்மதம்." Does சம்மதம் fit "comfortable"?
21. 10 HR round, intro: heavy English mixing. Is it OK?

## Also note
- Two interview lessons name real employers (Infosys, TCS) and Anna University for realism. Say if you'd prefer generic names.
