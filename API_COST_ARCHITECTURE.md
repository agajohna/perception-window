# Curiosity Labs — API Cost & Architecture

## Main conclusion

API cost should be manageable because Curiosity is intentionally **sparse**.

We are not analyzing a continuous video stream. The interaction is:

```
Curiosity occurs
→ user lifts phone
→ holds the eye
→ app selects one good frame
→ one analysis request
→ release
→ stop
```

The product philosophy is also the cost-control strategy.

**Never send a frame merely because the camera produced one. Send it because a moment of curiosity deserves an answer.**

## Expensive architecture to avoid

Do not:

- Send live video continuously.
- Analyze a frame every second during the entire hold.
- Upload full-resolution iPhone images unnecessarily.
- Retry requests invisibly without limits.
- Send the entire observation history with every comparison.
- Use the largest model for subject matching and every minor task.

That architecture would become unnecessarily costly and slow.

## Recommended analysis funnel

### 1. On-device preparation

Use Apple Vision and local logic to:

- Wait for a stable frame.
- Detect blur or poor exposure.
- Determine the likely region of interest.
- Crop around the subject.
- Resize the image appropriately.
- Avoid duplicate requests.
- Perform preliminary subject matching.

**No API call should happen yet.**

### 2. Select one frame

During a curiosity session, choose the best available frame rather than sending every frame.

For the initial demo, **one request per completed eye hold** is enough.

### 3. Route by task

Use the cheapest suitable path for each operation:

| Task | Path |
|---|---|
| Subject retrieval/matching | Preferably local |
| First meaningful observation | Small vision-capable model |
| Continuity comparison | Current frame + most relevant prior frame |
| Difficult or uncertain cases | Optionally escalate to a stronger model later |

### 4. Keep output extremely short

The API should return structured data and one restrained user-facing sentence—not an essay.

Example with change:

```json
{
  "subject_match": true,
  "meaningful_change": true,
  "observation": "One flower bud has opened since Monday.",
  "evidence": ["Previously closed bud is now visibly open"],
  "comparison_confidence": 0.88,
  "silence_reason": null
}
```

Example with honest silence:

```json
{
  "subject_match": true,
  "meaningful_change": false,
  "observation": null,
  "evidence": [],
  "comparison_confidence": 0.81,
  "silence_reason": "no_meaningful_change"
}
```

The interface remains silent.

## Continuity request design

For a revisit, send only what is required:

- Current cropped image.
- Best prior comparison image.
- Dates of both observations.
- Stable internal entity ID.
- Small amount of relevant history or structured findings.

Do not send every historical image.

Later, retrieval should choose among:

- Most recent observation.
- Baseline observation.
- Best visually comparable observation.
- Same growth stage or season.

The immediately previous image is sufficient for the first version but should not become a permanent architectural limitation.

## Session deduplication

Repeated scans within a short period should be treated as one curiosity session.

Suggested initial rule:

```
Same probable subject + within roughly two minutes = continued inspection, not a new historical visit
```

This prevents unnecessary API charges and avoids manufacturing meaningless continuity statements between nearly identical frames.

## Store evidence separately from interpretation

Each saved observation should include:

- Persistent entity ID
- Temporary subject key
- Timestamp
- Source image
- Cropped comparison image
- Camera/image metadata
- Place context, when available
- Structured visual findings
- User-facing observation
- Model and prompt version
- API status

The sentence shown to the user is an interpretation. Retaining the original evidence allows future models to reassess the history.

## Silence must have internal states

The UI may show nothing, but internally distinguish:

- No meaningful change
- Insufficient image quality
- Uncertain subject match
- Comparison unavailable
- Model refusal
- Network failure
- Rate limit
- API failure

These must not all be recorded as "nothing changed."

## Security requirement

`Secrets.plist` is acceptable only for local prototyping.

**Do not ship an OpenAI API key inside the iOS application.**

Production flow should be:

```
iPhone app → Curiosity backend → OpenAI API
```

The backend should handle:

- Authentication
- Per-user quotas
- Spend limits
- Image resizing and validation
- Request deduplication
- Model routing
- Rate limiting
- Logging without unnecessary image retention
- Emergency shutoff
- Prompt and model versioning

## Usage limits for the prototype

Add guardrails now, even if they are generous:

- Maximum one analysis per completed eye hold.
- Cooldown for near-identical requests.
- Daily request ceiling.
- Maximum image dimensions.
- Short response-token limit.
- No automatic retry loops.
- Log estimated cost per request.
- Log which stage caused the API call.

This lets us understand whether the product's natural usage pattern is economically viable.

## Product principle

Cost optimization must not damage the interaction.

The user should never feel that the product is rationing curiosity. Most savings should come from intelligent local preparation and avoiding redundant calls—not from adding menus, confirmation screens, or extra taps.

**Optimize the pipeline, not the human flow.**

## Immediate implementation order

1. Keep subject matching and frame-quality checks on-device where practical.
2. Add stable session deduplication.
3. Crop and resize before uploading.
4. Define structured JSON contracts for first observations and comparisons.
5. Add token/output limits and request accounting.
6. Route API calls through a small backend before any external testing.
7. Test with the same coffee tree across several actual days.
8. Measure cost per meaningful observation—not merely cost per request.

The key economic metric should eventually be:

**Cost per useful "Ah."**

Not cost per image and not requests per minute.

## Final architecture principle

- The camera sees continuously.
- The app samples selectively.
- The API reasons only when invited.
- Continuity remembers what matters.

**Recognition creates a record. Continuity creates a relationship.**
