---
name: image-prompting
description: Author prompts for image-generation tools — covers, thumbnails, post visuals, illustrations, infographics, logos; intake→spec→prompt→verify loop.
allowed-tools: Read Write Edit Grep Glob
model: inherit
current_aal: 1
target_aal: 1
---

# Image Prompting — Playbook for Generation Prompts

A reusable method for turning a content brief into a precise, repeatable prompt for a modern instruction-following image generator (the gpt-image family and equivalents). Load this whenever a task needs a visual asset: a blog cover, a video thumbnail, a social-post image, an inline illustration, a diagram/infographic, a logo mark, or an edit of an existing image.

This skill produces a **prompt and a verification pass**, not the image itself. It does not call any rendering API — it gives the caller the text to feed one, plus the size/quality settings to request and a checklist to judge the result.

## Core Principle

A generator renders what it can resolve from the words it is given. Two failure modes dominate: **under-specification** (it invents the parts you left blank) and **drift** (across edits or iterations, the parts you wanted kept silently change). The whole playbook is built to defeat both:

1. **Name every load-bearing decision.** Subject, medium, framing, light, palette, and any literal text are decisions — if you do not state them, the model decides for you, differently each run.
2. **Separate what must change from what must stay.** State invariants explicitly and repeat them on every iteration. This is the single highest-leverage habit; skipping it is why "just make the sky bluer" also moves the horizon.
3. **Change one variable per pass.** Isolated edits are debuggable; rewrites are not.

## The Loop

```
intake → spec → prompt → render → verify → (refine one variable) → ship
```

Stay in `spec` until the brief is unambiguous. Most wasted renders trace to a thin spec, not a weak model.

---

## 1. Intake — brief to spec

Before writing a single prompt word, resolve these from the task brief (ask only if the answer changes the image; otherwise pick a sane default and note it):

| Slot | Question | Default if silent |
|------|----------|-------------------|
| **Purpose** | Cover, thumbnail, post image, illustration, infographic, logo, edit? | infer from where the asset will be used |
| **Subject** | What is literally in the frame? | the brief's headline noun |
| **Placement** | Where will it live (platform, page region)? | drives aspect ratio — see §10 |
| **Text-in-image** | Any words rendered *inside* the image? Exact string? | none — keep text out, overlay later |
| **Brand/style anchor** | A palette, a prior asset, a house style to match? | neutral, clean, modern |
| **Mood** | One or two adjectives for the feeling | matches the content tone |
| **Hard noes** | Anything that must NOT appear | no watermark, no stray text, no logos |

State the **purpose explicitly in the prompt** ("a blog cover image", "a UI mockup", "an infographic") — it switches the model into the right rendering mode and changes its defaults for layout, text density, and realism.

---

## 2. Prompt Anatomy

Order the prompt from the outside in, so the model establishes the scene before it places detail. A reliable slot order:

```
[purpose/medium] → [scene/background] → [subject + pose/action] →
[key details] → [composition/framing] → [light] → [palette/mood] →
[literal text, in quotes] → [negative constraints / invariants]
```

Format is flexible — a clean descriptive paragraph, a line-per-slot list, or a tagged/structured block all work. For anything you will reuse or hand to another agent, **prefer the line-per-slot form**: it is maintainable, diffable, and easy to vary one slot at a time. Cleverness in syntax buys nothing; clarity does.

A minimal prompt is often enough; add detail only where the default would be wrong. Long prompts work but are harder to debug — grow them by isolated additions, not by front-loading every adjective you can think of.

---

## 3. Composition

Composition is the cheapest lever on perceived quality. Specify:

- **Framing / crop** — close-up, medium, wide, overhead/flat-lay, extreme close-up macro.
- **Camera angle** — eye-level, low angle (subject looms), high angle (subject diminished), Dutch tilt for tension.
- **Subject placement** — "centered", "rule-of-thirds, subject left", "subject lower-right with negative space upper-left for overlay text".
- **Depth** — clear foreground / midground / background, or flat with no depth for graphic styles.
- **Negative space** — reserve it deliberately when text or a logo will be composited on top later. This is the move that makes covers and thumbnails usable.

For people and creatures, also pin **body crop** ("full body, feet included" vs "head and shoulders"), **gaze** ("looking off-frame, not at camera"), **scale** ("child-sized against the table"), and **interaction** ("hands gripping the handle"). These fix the three things generators get wrong most: proportion, action geometry, and where the eyes point.

---

## 4. Style & Medium

State the **visual medium** first — it is the largest stylistic switch:

- Photograph, 3D render, flat vector, watercolor, oil, gouache, ink line art, pixel art, matte painting, isometric, paper-cut/collage, claymation.

Then layer **style qualifiers** only as needed: brushstroke texture, film grain, halftone, cel shading, soft outlines, high detail vs minimal. Add quality levers (grain, macro detail, textured strokes) sparingly and only when the bare medium reads too clean.

Name a **concrete reference register** rather than an artist's name where possible ("editorial magazine illustration", "children's picture-book", "technical blueprint", "premium product photography") — it transfers a whole aesthetic without copying any one person and keeps the output reusable.

For **character/brand consistency across a series**: lock an anchor description once (appearance, proportions, outfit, palette, demeanor) and on every later image instruct "same character, do not redesign — new scene only", restating the anchor traits each time. Style continuity must be named, not assumed.

---

## 5. Camera & Lens (for photoreal)

Reach for these only when the target is photographic realism:

- Use the explicit word **"photorealistic"** to engage the realism pathway.
- **Focal length** — wide (24–35mm) for environments and a sense of place; standard (50mm) for natural framing; portrait/tele (85–135mm) for flattering subjects and compression.
- **Aperture / depth of field** — "shallow depth of field, background bokeh" vs "deep focus, everything sharp".
- **Film / sensor cues** — "35mm film", "film grain", "natural color balance".
- **Authenticity markers** — pores, skin texture, fabric wear, weathering, slight asymmetry. Their absence is what makes an image read as plastic/AI.
- **Avoid** studio gloss and over-retouching unless the brief is explicitly a polished product shot.

---

## 6. Light

Light sets realism and mood more than any other single factor:

- **Direction** — front, side (sculpts form), back (rim/silhouette), top, three-quarter key.
- **Quality** — soft/diffused (overcast, softbox) vs hard (direct sun, single bulb) with crisp shadows.
- **Time / temperature** — golden hour (warm, long shadows), blue hour, midday (flat, hard), neon night, candlelit.
- **Special** — volumetric god-rays, rim light, practical light sources in frame, high-key (bright, airy) vs low-key (dark, dramatic).

For edits that change weather or time of day, change **only** the light and atmosphere and explicitly preserve camera angle, object positions, and scene identity.

---

## 7. Mood & Palette

- **Mood** — one or two adjectives carried through the whole prompt: serene, tense, playful, austere, nostalgic, energetic. Let it steer light, color, and pose rather than stating it once and contradicting it elsewhere.
- **Palette** — name it concretely: "muted earth tones", "high-contrast black and red", "pastel triad", "monochrome teal", or give explicit hex anchors when matching a brand. State whether it is warm or cool, saturated or desaturated, high or low contrast.
- For **atmospheric wide scenes** (cinematic, dark, rainy, neon), amplify scale, atmosphere, and color to hold the mood even when surface realism softens.

---

## 8. Text in Image

Rendering legible text is the hardest thing these models do. When the brief truly needs words baked into the image:

- Put the **exact string in quotation marks** or CAPITALS: `the word "LAUNCH" in bold sans-serif`.
- Specify typography as **constraints**: weight, size relative to frame, color, alignment, placement.
- **One appearance only** — add "render this text once, no repeated or extra text" (duplication is the default failure).
- For rare/branded/long words, **spell it out character by character** to fix symbol order.
- Request a higher quality tier for fine, dense, or multi-font text (see §10).
- Iterate text separately — small wording or layout tweaks fix legibility faster than re-rolling the whole image.

**Default to keeping text OUT of the generated image** and compositing it in a layout tool afterward. It is more legible, more on-brand, and trivially editable. Bake text in only when it must interact with the scene (a sign, packaging, a poster within the world).

---

## 9. Negative Constraints & Invariants

Two distinct tools — do not conflate them:

- **Exclusions** (what must not appear): "no watermark", "no extra text", "no logos or trademarks", "no extra fingers", "no border", "no signature".
- **Invariants** (what must be preserved, mostly for edits): "keep the same face, pose, and background", "preserve layout, geometry, and brand colors", "change only X, keep everything else identical".

Rules for invariants:

1. **List them explicitly** — the model will not infer "obviously keep the logo".
2. **Repeat the full invariant list on every iteration** — they do not persist across turns; dropping them is the #1 cause of drift.
3. **For surgical edits, enumerate the untouchables**: "do not change saturation, contrast, layout, captions, camera angle, or surrounding objects."

---

## 10. Native Aspect Ratio & Size (gpt-image-style tools)

Modern instruction generators render at a native size you request, rather than a fixed square you upscale. Request the aspect ratio the placement actually needs and let the tool render it natively:

| Placement | Aspect | Typical native size |
|-----------|--------|---------------------|
| Blog/article cover, OG image | 16:9 / 1.91:1 | landscape ~1536×1024 |
| Video thumbnail | 16:9 | landscape ~1536×864–1024 |
| Vertical story / reel / pin | 9:16 / 2:3 | portrait ~1024×1536 |
| Square post | 1:1 | 1024×1024 |
| Slide / deck | 16:9 | landscape ~1536×864 |

Practical constraints for the gpt-image family (verify against your tool's current limits before shipping a pipeline):

- **Both sides multiples of 16**; longest side under the model's max (commonly < 3840 px).
- **Aspect ratio within ~3:1** — extreme banners are out of native range; render closer to range and crop.
- **Total pixels within the model's band** (roughly 0.65–8.3 megapixels for the larger models).
- **Do not generate a square and stretch it.** Request the native aspect — geometry and composition stay correct.

**Quality vs. cost tiers:**

- Start at the **low/draft** tier for ideation, high volume, or latency-sensitive work; confirm it is good enough.
- Step up to **medium/high** for fine or dense text, detailed infographics, large portraits, and identity-sensitive edits.
- Use a **mini/fast** model for batch ideation and previews where throughput beats peak quality.
- For edits that must preserve a subject's identity through a large change, request **high input fidelity** if the tool exposes it.

---

## 11. Iterative Refinement

1. Start from a clean, minimal base prompt — establish the skeleton works before adding detail.
2. **Change one variable per pass.** Adjust light, *or* palette, *or* framing — never three at once — so you can attribute the change.
3. Use context references ("same style as before", "the subject") but **restate the critical details** anyway; the model drifts when it relies on memory alone.
4. For edits, paste the **full invariant list** every time.
5. Prefer small wording adjustments over rewrites — they usually improve composition and text more reliably than starting over.
6. Keep a short log of which knob moved the needle — it becomes the seed for the next similar asset and feeds your reusable templates.

---

## 12. Editing an Existing Image

Edit prompts are a special case of §9: the scene already exists, so almost everything is an invariant. The shape is always:

```
[the single change] + [keep everything else identical] + [enumerate the untouchables]
```

Common edits and their one-line forms:

- **Object swap** — "Replace only the chair with a leather armchair. Keep camera angle, lighting, shadows, and all other objects unchanged."
- **Object removal** — "Remove the trash can. Change nothing else; fill the gap with plausible matching detail."
- **Background / weather / time** — "Make it a rainy dusk. Keep subject, pose, and framing; change only light, sky, and wet surfaces."
- **Style transfer** — "Apply the watercolor style of the reference to this subject. Keep the composition and framing."
- **Compositing** — reference each input by index ("Image 1: the product; Image 2: the kitchen scene"), state what moves where, and match scale, perspective, and light to the destination.

When the tool supports it, request **high input fidelity** for edits that must hold identity through a big change.

---

## Reusable Templates

Fill-in-the-blank prompt skeletons for the common asset types (cover, thumbnail, social post, illustration, infographic, logo, photoreal, edit) live in [`prompt-templates.md`](prompt-templates.md). Copy the one matching the purpose, fill the slots from the §1 intake, and tune one variable at a time.

---

## Verification Checklist

Run before shipping any generated asset:

- [ ] **Purpose fit** — reads correctly at its real display size (thumbnail legible when small; cover works behind overlay text)?
- [ ] **Subject** — the intended subject is present, recognizable, correctly proportioned?
- [ ] **Composition** — framing, balance, and reserved negative space match the spec?
- [ ] **Text** — every baked-in word is spelled correctly, rendered once, legible; no stray/duplicated text?
- [ ] **Invariants** — for edits, everything that should be untouched is untouched?
- [ ] **Exclusions** — no watermark, no unintended logos/trademarks, no signature, no extra limbs/fingers?
- [ ] **Aspect/size** — native aspect matches the placement; no stretching; resolution sufficient for use?
- [ ] **Brand/style** — palette, medium, and mood match the anchor; consistent with sibling assets in a series?
- [ ] **Rights/safety** — no recognizable real person used without basis, no copyrighted character or trademarked mark unless intended and cleared?
- [ ] **Refinement budget** — if not shipping, the next pass changes exactly one variable.

---

## Gotchas

- **Silence is a decision delegated to the model.** Anything unstated is randomized per run. Pin the load-bearing slots.
- **Invariants evaporate between turns.** Always repeat the full keep-list on edits and iterations.
- **Baked-in text is brittle.** Default to overlaying text later; bake it only when it must live in the scene.
- **Square-then-stretch ruins composition.** Request the native aspect ratio.
- **More adjectives ≠ better.** Past a point they fight each other. Add detail only where the default is wrong, one slot at a time.
- **Artist-name copying is a rights and reuse trap.** Name a style register or genre instead.
- **Quality tier is a real knob, not decoration.** Drop it for ideation, raise it for text and identity-critical work.

---

## Context Loading

Related skills, load when relevant:

- `writing` / `publishing` — when the image accompanies an article or post; align mood and palette with the copy and respect platform image specs.
- `frontend-ui` — when the asset is a UI mockup or must match a site's theme tokens and aspect ratios.
- `brainstorming` — when the visual concept itself is open and needs exploration before a spec exists.
