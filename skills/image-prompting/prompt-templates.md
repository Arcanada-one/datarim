# Reusable Prompt Templates

Fill-in-the-blank skeletons for the common asset types. Pick the one matching the §1 Purpose, fill the `{slots}` from intake, then refine one variable per pass (SKILL.md §11). Square brackets mark optional slots. Keep literal in-image text in quotes; default to overlaying text later (SKILL.md §8).

Each template ends with a **render request line** — the size/quality settings to ask the tool for (SKILL.md §10).

---

## Blog / Article Cover (landscape, overlay-ready)

```
A {medium, e.g. editorial illustration / photorealistic photo} for a blog cover about {topic}.
Scene: {background/setting}.
Subject: {main subject}, {placement, e.g. lower-right}, with generous negative space {where} for headline overlay.
Composition: wide framing, {eye-level / high angle}, clear focal point.
Light: {soft daylight / golden hour / studio}.
Palette & mood: {palette}, {mood adjectives}.
No text in the image. No watermark, no logos.
Render: 16:9 native landscape (~1536×1024), medium quality.
```

## Video Thumbnail (must read at small size)

```
A bold, high-contrast {medium} thumbnail for a video about {topic}.
Subject: {single clear subject / expressive face}, large in frame, {gaze/expression}.
Composition: 16:9, subject {centered / left}, simple uncluttered background, strong figure-ground separation.
Light: punchy, high-key, crisp.
Palette: saturated {2-3 colors}, high contrast so it pops at thumbnail size.
[Optional in-image text: the word "{WORD}" in heavy sans-serif, {placement}, rendered once, large.]
No watermark, no extra text, no busy detail.
Render: 16:9 native landscape, high quality (text legibility).
```

## Social Post Image (square or vertical)

```
A {medium} image for a {platform} post about {topic}.
Scene: {setting}. Subject: {subject}, {pose/action}.
Composition: {1:1 square / 9:16 vertical}, {placement}, room for caption overlay {where}.
Light: {light}. Palette & mood: {palette}, {mood}.
On-brand with {brand/style anchor}.
No text in image, no watermark, no logos.
Render: {1:1 1024×1024 / 9:16 ~1024×1536}, medium quality.
```

## Inline Illustration (supports a passage)

```
A {flat vector / watercolor / line-art} illustration depicting {concept/metaphor}.
Subject: {subject and any symbolic elements}.
Style: {soft outlines / textured / minimal}, {reference register, e.g. picture-book / technical}.
Composition: {framing}, balanced, {negative space if wrapping text}.
Palette & mood: {palette}, {mood}.
No text, no watermark.
Render: {aspect for the layout slot}, medium quality.
```

## Infographic / Diagram

```
A clean infographic explaining {subject} for {audience level}.
Information flow: {left-to-right / top-down / radial}; components: {list the labeled blocks/steps}.
Visual language: flat icons, unified icon style, clear arrows, generous white space, professional and minimal.
Required labels (render exactly, once each): "{label 1}", "{label 2}", "{label 3}".
No decorative noise, no clipart, no stock photos, no gradients or drop shadows.
Render: {16:9 landscape / portrait per use}, high quality (dense small text).
```

## Logo / Brand Mark

```
An original, simple, scalable logo mark for {brand}, conveying {brand character/values}.
Design: {flat / geometric / monoline}, strong silhouette, works in monochrome, vector-clean, minimal ornament.
Palette: {1-2 colors} on a single solid background.
Usage: must stay legible from favicon to billboard.
No watermark, no extra text, no existing brand's logo, original design only.
Render: 1:1 1024×1024, high quality; [generate {n} variants].
```

## Photoreal Scene / Product

```
A photorealistic photograph of {subject} in {setting}.
Camera: {50mm standard / 85mm portrait / 24mm wide}, {shallow depth of field, background bokeh / deep focus}.
Light: {golden hour / softbox studio / overcast}, natural color balance.
Detail: realistic texture — {pores / fabric weave / material wear}, subtle asymmetry; no over-retouching, no studio gloss.
Palette & mood: {palette}, {mood}.
No watermark, no text, no logos.
Render: {aspect}, high quality.
```

## Edit of an Existing Image

```
{The single change, e.g. "Replace only the sofa with a green velvet sofa."}
Keep everything else identical: camera angle, lighting, shadows, layout, and all surrounding objects unchanged.
Do not change saturation, contrast, framing, or any text already in the image.
[Use high input fidelity to preserve identity.]
```

## Multi-Image Composite

```
Image 1: {description of source element}. Image 2: {description of destination scene}.
Take the {element} from Image 1 and place it into Image 2 at {location}.
Match Image 2's scale, perspective, lighting direction, and color temperature so it does not look pasted.
Keep Image 2's background and framing. Change nothing else.
[Use high input fidelity.]
```
