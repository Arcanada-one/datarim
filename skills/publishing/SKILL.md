---
name: publishing
description: Technical rules for publishing content to social media and websites — platform limits, formatting, API patterns, OG tags, multi-platform workflow.
model: inherit
current_aal: 1
target_aal: 2
---

# Publishing — Technical Rules for Content Distribution

Rules for the **technical act** of publishing ready content to platforms. This skill does NOT cover writing (see `writing` skill) or quality review (see `humanize`, `factcheck` skills). It covers: how to format, what limits apply, how to post correctly.

Credentials, channel URLs, bot tokens, and site-specific config live outside this skill (typically in credentials files or project config).

## Publishing channel — one tool, no ad-hoc scripts

When the deployment provides a **dedicated publishing application** (in the Arcanada ecosystem this is the Publisher at `Projects/Publisher/code/arcanada-publisher` — a browser-automation CLI + localhost HTTP API with per-platform adapters), ALL external publishing goes through it and nothing else:

- **Social media and external sites** (Facebook, LinkedIn, X/Twitter, Reddit, VKontakte, any external destination) — publish ONLY through that application. Do NOT hand-roll one-off Playwright/`curl` scripts, do NOT post manually from an agent, do NOT stand up a parallel publisher. If the app fails, is not authenticated, or lacks a rule for the case at hand — **fix the app** (adapter, selector, docs rule, re-run its `login`), never route around it.
- **Own/first-party sites** — publish ONLY via push to the repo's `main` on the code host (then CI/CD or the project's `deploy.sh` syncs to prod). Never edit files directly on a server.
- Telegram Bot API remains a valid channel (it is one of the publisher's own transports / a first-party bot); its safety rules are in `Projects/Publisher/code/arcanada-publisher/docs/reference/telegram-bot-api-publish-safety.md`.

Standalone per-platform publisher CLIs that predate the consolidated app are retired once their capability is absorbed — do not resurrect them.

---

## Platform Limits

### Telegram (Bot API)

| Method | Max text | Formatting |
|--------|----------|------------|
| `sendMessage` text | 4096 chars | HTML or MarkdownV2 |
| `sendPhoto` caption | 1024 chars | HTML or MarkdownV2 |
| `sendVideo` caption | 1024 chars | HTML or MarkdownV2 |
| `sendDocument` caption | 1024 chars | HTML or MarkdownV2 |
| `sendMediaGroup` caption | 1024 chars per item (only **first** item's caption is rendered in the album UI) | HTML or MarkdownV2 |

**Character counting (CRITICAL)**:
Telegram counts limits in **UTF-16 code units**, not Unicode codepoints, not bytes. Practical impact:
- RU Cyrillic in BMP = 1 unit per char → `len(text)` in Python matches 1:1.
- Most emoji (`😀`, `🚀`, `🇷🇺` flags) = 2 units each (surrogate pair).
- ZWJ family emoji (`👨‍👩‍👧`) = 2+N units (multiple surrogate pairs + ZWJ joiners).
- Naive `len(text)` underestimates the count for any text with emoji/symbols outside BMP.

Canonical Python counter (use this before every sendMessage/sendPhoto for limit checks):

```python
def telegram_units(text: str) -> int:
    """Return UTF-16 code-unit count — what Telegram measures against 4096/1024 limits."""
    return len(text.encode("utf-16-le")) // 2
```

**Supported HTML**: `<b>`, `<i>`, `<u>`, `<s>`, `<a href="">`, `<code>`, `<pre>`, `<blockquote>`, `<tg-spoiler>`, `<tg-emoji>`
**Not supported**: `<h1>`–`<h6>`, `<p>`, `<br>`, `<div>`, `<table>`, `<img>`
Use `parse_mode=HTML` (preferred) or `parse_mode=MarkdownV2`.

**Output encoding (MANDATORY before any sendMessage/sendPhoto/sendMediaGroup with `parse_mode=HTML`)**: a literal `&`, `<`, or `>` in raw text triggers `400 Bad Request: can't parse entities`. Worse, unescaped `<a href="javascript:…">` survives to some Telegram clients/mirrors. Sanitise via the canonical mask-then-emit pattern (a raw regex cannot uniformly cover single-quoted, unquoted, and whitespace-around-`=` attribute forms — use `html.parser`):

```python
import html
import re
from html.parser import HTMLParser

ALLOWED_TAGS = frozenset({
    "b", "strong", "i", "em", "u", "ins", "s", "strike", "del",
    "a", "code", "pre", "blockquote", "tg-spoiler", "tg-emoji",
})
# Per-tag attribute allowlist. Tags absent here MUST carry no attributes.
ALLOWED_ATTRS = {
    "a":        frozenset({"href"}),
    "code":     frozenset({"class"}),      # only class="language-…" (fullmatch)
    "tg-emoji": frozenset({"emoji-id"}),   # only numeric value
}
ALLOWED_HREF_SCHEMES = ("http://", "https://", "tg://", "mailto:", "tel:")
LANGUAGE_CLASS_RE = re.compile(r"language-[A-Za-z0-9_+\-]{1,32}")  # closed grammar: alphanum + `_+-`, 1..32 chars
MAX_NESTING = 64                            # defence-in-depth ceiling; realistic Telegram input never exceeds this


class _SafeHTML(HTMLParser):
    """Parses input via html.parser, escapes data, and re-emits only whitelisted tags
    with the per-tag attribute allowlist applied. Parallel stack tracks whether each
    opened allowed tag was emitted or dropped, so the matching closing tag is
    suppressed when the opening was dropped (no orphaned `</a>`)."""

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.out = []
        self._stack = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return                         # disallowed tag — dropped (closing also dropped)
        if len(self._stack) >= MAX_NESTING:
            self._stack.append((tag, "drop"))   # nesting overflow → drop tag, preserve content
            return
        if not self._attrs_ok(tag, attrs):
            self._stack.append((tag, "drop"))
            return
        rendered = " ".join(
            f'{name.lower()}="{html.escape(value, quote=True)}"'
            for name, value in attrs
        )
        self.out.append(f"<{tag}{(' ' + rendered) if rendered else ''}>")
        self._stack.append((tag, "emit"))

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return
        for i in range(len(self._stack) - 1, -1, -1):
            if self._stack[i][0] == tag:
                _, action = self._stack.pop(i)
                if action == "emit":
                    self.out.append(f"</{tag}>")
                return
        # orphan endtag — dropped silently

    def handle_data(self, data):
        self.out.append(html.escape(data, quote=False))

    def handle_entityref(self, name):
        self.out.append(f"&{name};")       # preserve already-encoded entity

    def handle_charref(self, name):
        self.out.append(f"&#{name};")      # preserve already-encoded numeric

    def _attrs_ok(self, tag, attrs):
        # Note: html.parser pre-decodes entity references inside attribute values
        # even with convert_charrefs=False — `<a href="&#106;avascript:…">` arrives
        # at this method with `value` already decoded to `javascript:…`. Do NOT add
        # html.unescape() here — it would double-decode and break the scheme guard.
        allowed = ALLOWED_ATTRS.get(tag, frozenset())
        seen = set()
        for name, value in attrs:
            name = name.lower()
            if name not in allowed or value is None:
                return False
            seen.add(name)
            if tag == "a" and name == "href" \
                    and not value.lower().startswith(ALLOWED_HREF_SCHEMES):
                return False
            if tag == "tg-emoji" and name == "emoji-id" and not value.isdigit():
                return False
            if tag == "code" and name == "class" \
                    and not LANGUAGE_CLASS_RE.fullmatch(value):
                return False
        if tag == "a" and "href" not in seen:
            return False                   # <a> without href is invalid for Telegram
        if tag == "tg-emoji" and "emoji-id" not in seen:
            return False
        return True


def tg_safe_html(text: str) -> str:
    """Sanitise free-form text for Telegram Bot API `parse_mode=HTML`.

    - Raw `&`, `<`, `>` are escaped (Telegram returns 400 otherwise).
    - Whitelisted tags round-trip unchanged (`<b>x</b>` → `<b>x</b>`).
    - Per-tag attribute allowlist enforced (`<a>` → only `href`; `<tg-emoji>` → numeric `emoji-id`; `<code>` → only `class="language-*"` matching the closed grammar `language-[A-Za-z0-9_+-]{1,32}`).
    - `<a>` with non-allowlist href scheme (`javascript:`, `data:`, `file:`, …) → tag dropped, inner text preserved.
    - Disallowed tags (`<script>`, `<h1>`, `<img>`, `<onclick>`-bearing tags) → tag dropped, inner text preserved.
    - Single-quoted / unquoted / whitespace-around-`=` attribute forms treated uniformly (no regex bypass).
    - Nesting overflow beyond `MAX_NESTING=64` levels drops the over-nested tag (inner text preserved). Telegram itself rejects deeply nested markup, so realistic input never trips this ceiling.

    Known content-fidelity caveats (NOT security issues; documented so operators don't get surprised):
    - Literal `<!--` opens an HTML comment that `html.parser` consumes through the next `-->` (or to end-of-input), dropping any markup in between (`<!-->` alone parses as an empty comment and does NOT swallow trailing text). If operator-quoted source text contains literal `<!--`, escape it (`&lt;!--`) before calling `tg_safe_html`.
    - Markup nested inside HTML raw-text elements (`<textarea>`, `<title>`, `<script>`, `<style>`) is delivered to the parser as text data, not parsed — so `<textarea><b>x</b></textarea>` flattens to `&lt;b&gt;x&lt;/b&gt;` (the inner tags escape, do not render). These wrapper tags are NOT in `ALLOWED_TAGS` and are dropped anyway; this note documents the side-effect on their inner content.
    """
    parser = _SafeHTML()
    parser.feed(text)
    parser.close()
    return "".join(parser.out)
```

**Unit test** — MUST pass before shipping any change to `tg_safe_html`. Run as `python3 -c "$(cat <impl-snippet>; cat <test-snippet>); _verify_tg_safe_html()"` or paste both blocks into a `.py` file and execute. Recommended pre-commit hook for repos that re-vendor this helper.

```python
def _verify_tg_safe_html():
    cases = [
        # Whitelisted round-trip
        ("<b>x</b>",                                           "<b>x</b>"),
        ('<a href="https://ok.com">link</a>',                  '<a href="https://ok.com">link</a>'),
        ('<a href="tg://user?id=1">u</a>',                     '<a href="tg://user?id=1">u</a>'),
        # Literal & < > escape
        ("5 < 7 & 7 > 3",                                      "5 &lt; 7 &amp; 7 &gt; 3"),
        # javascript: scheme dropped — all attribute shapes (regex would miss most of these)
        ('<a href="javascript:alert(1)">x</a>',                "x"),
        ("<a href='javascript:alert(1)'>x</a>",                "x"),
        ('<a href = "javascript:alert(1)">x</a>',              "x"),
        ('<a href=javascript:alert(1)>x</a>',                  "x"),
        # Out-of-allowlist attribute drops the tag (onclick / onmouseover / unknown class)
        ('<a href="https://ok.com" onclick="alert(1)">y</a>',  "y"),
        ('<a onmouseover="x()" href="https://ok.com">y</a>',   "y"),
        ('<b class="bold">x</b>',                              "x"),
        # tg-emoji guard — only numeric emoji-id
        ('<tg-emoji emoji-id="5368324170671202286">x</tg-emoji>',
         '<tg-emoji emoji-id="5368324170671202286">x</tg-emoji>'),
        ('<tg-emoji emoji-id="javascript:alert(1)">x</tg-emoji>', "x"),
        # code: only class matching LANGUAGE_CLASS_RE
        ('<code class="language-py">print(1)</code>',
         '<code class="language-py">print(1)</code>'),
        ('<code class="language-c++">x</code>',
         '<code class="language-c++">x</code>'),
        ('<code class="language-shell_session">x</code>',
         '<code class="language-shell_session">x</code>'),
        ('<code class="random">x</code>',                      "x"),
        # code class — tightened grammar rejects path-traversal / whitespace / overlong
        ('<code class="language-../../etc/passwd">x</code>',   "x"),
        ('<code class="language-py danger">x</code>',          "x"),
        ('<code class="language-this-name-is-far-too-long-to-be-a-valid-language-identifier">x</code>', "x"),
        # Disallowed tags dropped, inner text preserved
        ("<script>alert(1)</script>",                          "alert(1)"),
        ("<h1>Title</h1>",                                     "Title"),
        ("<img src='x'>after",                                 "after"),
        # <a> without href / with empty href is dropped (Telegram requires a real href)
        ("<a>x</a>",                                           "x"),
        ('<a href="">x</a>',                                   "x"),
        # Already-escaped entities preserved (idempotency)
        ("5 &lt; 7",                                           "5 &lt; 7"),
        ("&#60;b&#62;",                                        "&#60;b&#62;"),
    ]
    failures = []
    for src, expected in cases:
        got = tg_safe_html(src)
        if got != expected:
            failures.append(f"  src={src!r}\n  got={got!r}\n  expected={expected!r}")
    if failures:
        raise AssertionError("tg_safe_html failures:\n" + "\n".join(failures))
    # MAX_NESTING boundary — separate because expected output is parameterised on the constant
    deep_src = "<b>" * (MAX_NESTING + 36) + "x" + "</b>" * (MAX_NESTING + 36)
    deep_expected = "<b>" * MAX_NESTING + "x" + "</b>" * MAX_NESTING
    deep_got = tg_safe_html(deep_src)
    if deep_got != deep_expected:
        raise AssertionError(f"MAX_NESTING boundary FAIL: got {len(deep_got)} chars, expected {len(deep_expected)}")
    print(f"tg_safe_html: {len(cases)}/{len(cases)} pass + MAX_NESTING={MAX_NESTING} boundary OK")
```

Disallowed tags are dropped and their inner text is preserved as plain escaped data — `<script>alert(1)</script>` becomes `alert(1)`, with no execution path opened. The allowlist of href schemes MUST be enforced operator-side — Telegram's own filter is inconsistent across clients and is not a defence boundary.

**Photo + caption decision tree** (input: `post_text`, optional `photo`):

```
units = telegram_units(post_text)

if not photo:
    if units <= 4096:      → sendMessage(chat_id, text=post_text, parse_mode=HTML)
    else:                  → split-policy Pattern B (text-thread, see below)

elif photo and units <= 1024:
    → sendPhoto(chat_id, photo=photo, caption=post_text, parse_mode=HTML)

elif photo and units <= 5096:        # 1024 caption + 4096 reply = Pattern A
    teaser = first_chunk(post_text, max_units=1024)
    rest   = post_text[len_codepoints(teaser):]
    photo_msg = sendPhoto(chat_id, photo=photo, caption=teaser, parse_mode=HTML)
    sendMessage(chat_id, text=rest, reply_to_message_id=photo_msg.message_id, parse_mode=HTML)

else:                                # units > 5096 → Pattern C (photo + N text-parts)
    → split-policy Pattern C (see below)
```

**Split policy for long posts** (Adaptive):

| Pattern | Use when | Layout |
|---------|----------|--------|
| **A** | `1024 < units ≤ 5096` AND photo present | `sendPhoto(caption=teaser≤1024)` → `sendMessage(reply_to=part1, text=rest≤4096)` |
| **B** | `units > 4096` AND no photo | `sendMessage` × N, each ≤4096, all reply-chained to part-1 msg_id |
| **C** | `units > 5096` AND photo present | `sendPhoto(caption="[1/N]" + teaser≤1015)` → `sendMessage(reply_to=part1, text="[i/N]" + chunk)` × (N−1) |

Numbering style: `[1/N]` **prefix** at start of every part (not footer; footer becomes invisible on truncation).
Budget the prefix: reserve ≈8 units in part-1 caption for `"[1/N] "` (N ≤ 9 = 6 units; safe 8).

Split-points priority (find the latest match within budget, in order):
1. Operator marker: `<!-- split-here -->` line OR stand-alone `---` HR
2. Paragraph boundary: `\n\n`
3. Sentence boundary: `[.!?] ` (followed by space)
4. Hard char limit (last resort — NEVER mid-word; back up to last space)

Python reference:

```python
def split_into_parts(text: str, max_units: int = 4096) -> list[str]:
    """Split text on best boundary ≤ max_units. Returns list of chunks."""
    parts, buf = [], text
    while telegram_units(buf) > max_units:
        # find latest boundary within budget (UTF-16-aware via codepoint scan + measure)
        cut = _find_split_point(buf, max_units)   # tries markers → \n\n → ". " → space
        parts.append(buf[:cut].rstrip())
        buf = buf[cut:].lstrip()
    parts.append(buf)
    return parts
```

**Comments on channel posts** (canonical recipe, Bot API v10.0+):

`reply_to_message_id` on a channel post creates ANOTHER channel post (a quote), NOT a comment.
Anti-pattern: `message_thread_id` — that's for forum topics in supergroups, NOT channel comments.
To post a real comment under a channel post:

1. **Resolve linked group once and cache:** `linked = getChat(channel_id).linked_chat_id`.
2. **Publish to channel:** `channel_msg = sendMessage(channel_id, …)` → capture `channel_msg.message_id`.
3. **Poll for auto-forwarded copy** (Telegram auto-forwards channel posts into linked group within ~1 s). **Do NOT pass `offset` until a match is found** — `getUpdates(offset=N)` confirms (deletes from buffer) every earlier `update_id`, which can race-delete the forwarded copy before you scan it. Always poll with no offset; only confirm AFTER you have the match (or after the comment is posted, to drain the buffer):

   ```
   for attempt in 1..N:                       # N=10 recommended; ~1 s spacing
       updates = getUpdates(timeout=2)        # NO offset — see warning above
       for u in updates:
           m = u.channel_post or u.message
           if (m and m.chat.id == linked
                  and m.forward_origin
                  and m.forward_origin.type == "channel"
                  and m.forward_origin.chat.id == channel_id
                  and m.forward_origin.message_id == channel_msg.message_id):
               forwarded_msg_id = m.message_id
               # defensive (Bot API v6.2+): also require is_automatic_forward
               if m.get("is_automatic_forward") is True:
                   break-outer
               # without v6.2+ flag, the forward_origin conjunction is still safe
               break-outer
       sleep(1)
   ```

   Legacy fallback (older Bot API responses without `forward_origin`): match on `forward_from_chat.id == channel_id` AND `forward_from_message_id == channel_msg.message_id`.
4. **Reply in discussion group:** `comment = sendMessage(linked, reply_to_message_id=forwarded_msg_id, text=…)`.
5. **Post-publish verification gate (MANDATORY):** `assert comment.message_thread_id == forwarded_msg_id`. If not equal, the comment landed in the WRONG thread (some unrelated supergroup msg whose id happened to collide with `forwarded_msg_id`'s coordinate). Immediately `deleteMessage(linked, comment.message_id)` and re-run step 3 — auto-forward likely hadn't arrived yet. Do NOT proceed without this check.

<!-- gate:history-allowed -->
**Anti-patterns (concrete failure modes — verified 2026-05-20, CONTENT-0050 round 12 bug):**
<!-- /gate:history-allowed -->

- ❌ `reply_to_message_id = channel_msg.message_id` against the supergroup. `reply_to_message_id` is resolved in the **target chat's** namespace. In the supergroup namespace `channel_msg.message_id` points to whatever supergroup message happens to have that id — almost certainly NOT the auto-forwarded copy. Real failure: channel post 95 was auto-forwarded as supergroup msg 167; `reply_to=95` resolved to a stale supergroup msg in the part-2 thread → `message_thread_id=93` → comment invisible under channel post 95.
- ❌ Using `copyMessage(chat_id=supergroup, from_chat_id=supergroup, message_id=N)` as the "is the post forwarded?" probe. This returns success whenever supergroup msg N exists (regardless of whether N is an auto-forward or a regular user message). It also returns the **new copy** id, not the auto-forward id. Use the `getUpdates` discovery loop above — it is the only Bot-API path that yields the auto-forward msg id.
- ❌ `message_thread_id` as a sendMessage parameter to thread a comment. `message_thread_id` is a forum-topic feature for supergroups; for channel-discussion threading, Telegram derives the thread automatically from `reply_to_message_id` pointing at the auto-forward.
- ❌ Skipping step 5 verification. If the smoke run cannot be visually inspected in a Telegram client, `message_thread_id` returned by `sendMessage` is the only programmatic signal that threading worked.

Caching: `linked_chat_id` is stable per channel — store it in credentials alongside the channel `chat_id` so step 1 runs once, not per publish.

<!-- gate:history-allowed -->
**Test-channel smoke before prod (mandatory for new publisher code / first run after refactor):** before commenting on prod posts, replay the full sequence in `chat_id=-1003855619081` (Arcanada Test Channel) → `chat_id=-1003929851152` (Arcanada Test Comments). Reference smoke script: `/tmp/tg-smoke-correct-comment.py` (CONTENT-0050). Pass criterion: returned `comment.message_thread_id == forwarded_msg_id`.
<!-- /gate:history-allowed -->

## Post title — first line of the body on every platform

The article's title (or a title-equivalent headline in the post's language)
MUST be the **first line of the post body** on every social platform — X,
Facebook, LinkedIn, VK, Telegram — followed by a blank line, then the lead
paragraph. A post that opens straight into the lead (no title line) loses the
hook and forces the operator to hand-fix it. The cycle posts (A2/A3/…) always
lead with the title line — match that shape.

- **Telegram:** the title is the **bold** first line of the video caption (post 1).
- **X / FB / LinkedIn / VK:** the title is a **plain** first line (no `<b>` — those
  surfaces flatten HTML; only Telegram renders `<b>`). Follow with a blank line.
- Verify the title is present in the **read-back** content (not just the source
  file) before declaring smoke.

## Universal rule — links go in the first comment, not the body

For **all** social platforms (FB, LinkedIn, Telegram, VK, Twitter/X threads, etc.) the **post body must not contain a standalone "links block"** — a section header like `Куда смотреть` / `Ссылки` / `Resources` / `Полезное` followed by a bullet-list of URLs is forbidden in the body. All such CTA-links (blog URL, dashboards, repositories, doc cross-refs) MUST be published as the **author's first comment** under the post. <!-- allow-non-ascii: literal-russian-section-headers-fixture-for-publishing-rule -->

Rationale:
- **FB & LinkedIn algorithms** downrank posts that contain external links in the body — comment-level links bypass that penalty.
- **Reader UX** — the post body ends on a narrative beat; the link list lives in a single canonical place (the pinned/top comment).
- **Maintenance** — one comment to update if a URL changes, vs editing the rendered post (FB edit history is shown to readers).

Inline mentions in prose are fine (`Datarim (github.com/Arcanada-one/datarim, MIT) is open-source`, `Munera on muneral.com`). The rule targets **standalone link sections**, not contextual references.

Publisher pattern: immediately after `POST_URL` is captured, post the first-comment with the CTA-links block. On FB and LinkedIn that is a normal `Прокомментировать` action under the post; on Telegram it is the discussion-thread comment under the channel post (see canonical recipe above). If the platform's comment size is smaller than the link list, keep blog URL + 2–3 anchor links and rely on the website (`arcanada.one`) for the full directory. <!-- allow-non-ascii: literal-russian-fb-action-token-required-for-publisher-pattern -->

**Verify the comment's parent post before commenting — never trust a returned URL blindly.** A browser publisher can return the feed's top post or an older post, not the one just created. Before attaching the first comment, read back the target post (its body/media) and confirm it is **this** article published **this** cycle; only then comment. A comment that lands on a stale post is a silent defect the operator finds later by hand.

**The same "verify the target post" rule applies to the site's `social` back-link block.** Every permalink written into the article's `social` block (Telegram, X, LinkedIn, Facebook, VK) MUST be opened in a browser and confirmed to render OUR post of THIS cycle before deploy — a URL reused from a prepared `*-parent-url.txt`/memory can point at an unrelated older post, and `curl` HTTP 200 does not prove it (FB/LI/X serve 200 for wrong/deleted posts). Copy the working permalink verbatim; do not hand-build FB `pfbid`/LinkedIn `feed/update/urn:li:activity:` URLs. This has shipped a live back-link pointing at an unrelated older post (a reused FB `pfbid…` from a prepared parent-url file) — a silent defect the operator only catches by opening the link.

**Attach the hero image to image-capable posts.** When the post promotes an article that has a hero image, attach that image to the post itself — FB `--image-file`, LinkedIn `--image-file`, TG `sendPhoto`. A bare text post with no image loses badly in the feed, and an article's OG-preview from a *comment* link is not a substitute (the body shows no image). A FB post published text-only loses badly in the feed — there is no way to add media retroactively (UI edit replaces text only), so you must delete and re-publish, then re-add the first comment. Get the image right on the first publish.

Deletion and re-publication are separate irreversible public actions. Never infer
permission for them from the original campaign approval. If media is missing or
wrong after publication, freeze mutations, show the operator the exact post URL and
read-back evidence, and obtain explicit platform-specific permission before deleting,
re-publishing, editing, or adding a corrective comment.

**Video standard for social posts — animated cover (cover → cycling effects) over the article narration.** When a post has both a cover image AND article narration audio, the preferred attachment is NOT a static cover and NOT a plain cover+audio MP4, but an **animated screensaver video**: the post's cover shown clean for ~2 s, then a NEW visual effect every ~3 s cycling through a large randomly-shuffled pool, with smooth crossfades (~0.6 s) between effects, for the full length of the narration. The canonical generator is `Projects/Publisher/code/arcanada-publisher/dev-tools/video/make-cycle-video.sh <cover> <audio> <out.mp4> [intro_sec] [seg_sec] [seed]` — pure ffmpeg, no plugins. Rules:
- Inputs come **from the post itself**: the cover is the article's hero cover (the post-level cover, not an in-article inline preview), the audio is the article's own narration in the post language. The intro frame is always that cover.
- The effect order is **re-shuffled randomly every run** (Fisher-Yates over the pool) so two posts never get the same sequence; pass a fixed `seed` only to reproduce one.
- Video length always equals the narration length; narration plays from t=0 (the 2 s intro is the cover held still, not silence).
- **No audio?** Fall back to a ~30 s clip from the cover alone (the generator's no-audio path), still with cycling effects.
- Do NOT use a bare audio-waveform visualizer (showwaves/showcqt/showspectrum) as the WHOLE post video — a full-frame visualizer looks generic; the animated-cover cycle stays the hero. A bottom audio-amplitude STRIP drawn ON TOP of the cycle is allowed and is the default house style (operator-approved): a showwaves oscilloscope with a horizontal gold→crimson gradient, ~180px tall, pinned to the bottom edge, shown only when narration audio exists. The distinction is overlay-strip (good) vs. whole-frame-visualizer (forbidden). The canonical generator draws it by default; disable with the `--no-waveform` CLI flag (or `WAVEFORM=0` for the bash reference engine).
- Per-platform attach: X long-form and LinkedIn take the MP4; Facebook feed forces video into Reels, so on FB use the static cover image instead (keep the video for X and LinkedIn); Telegram can take the MP4 via `sendVideo`.
- **Approved-audio provenance is mandatory.** A narration-backed video may use only
  an MP3 that passed the semantic fidelity gate below. Record the approved MP3
  SHA-256 and frozen narration SHA-256 in the video generation evidence. After
  muxing, extract and transcribe the final MP4 audio and compare it with the approved
  narration. Codec, duration, dimensions, bitrate, waveform, and non-silence checks
  do not prove spoken content.

**Blog audio narration — TTS text prep (Russian / Silero).** The RU narration engine (Silero, via the speech sidecar) is Cyrillic-only: it cannot pronounce Latin words, bare numbers, currency, fractions, or percentages, and on a digit/symbol "soup" it returns a hard HTTP 500. The narration text MUST therefore be **normalized before TTS, not stripped**. Stripping the problem tokens (the path of least resistance, fine for benchmark tables where raw figures carry no spoken value) silently drops meaning in a narrative article — the listener hears gaps where numbers and product names should be.

> **MANDATE — normalize through the versioned lexicon, never ad-hoc scripts.** Blog narration MUST be run through a **single versioned lexicon-normalizer** committed to the site repo (a lexicon of acronym/name phonetics + stress overrides + pause rules, plus a normalizer that applies them automatically before TTS). Do NOT hand-write one-off normalization scripts per article — that path regresses the same pronunciation defects every time and forces the operator to proof-listen every word. When a word sounds wrong, add it to the lexicon (one line) rather than editing code. The normalizer runs automatically inside the audio generator; a deployment that provides one documents its exact module/lexicon paths and the RU-accent engine it uses (e.g. a neural accentuator as the homograph base plus an authoritative stress-override file for proper nouns) in that deployment's own runbook. The rules below are the *contract the lexicon must satisfy* — the deployment implements them once, in code, not per article:

<!-- allow-non-ascii-block: russian-tts-normalization-examples-are-the-literal-subject-of-this-content-work-skill -->
- **Numbers -> Russian words** via `num2words(n, lang="ru")`: `340` -> "триста сорок", `33%` -> "тридцать три процентов", `5,1` -> "пять и одна десятых". For `$14` emit only the number when the source already says "долларов" right after (else you get a doubled "долларов долларов").
- **Latin terms -> Cyrillic phonetics**, never left raw: product/brand names and abbreviations get a transliteration map (e.g. `Arcanada`->Арканада, `Datarim`->Датарим, `Muneral`->М+унерал, `Coworker`->Коворкер, `Telegram`->Телеграм, `Claude`->Клод, `README`->ридми, `PRD`->пи-эр-ди, `L4`->эль-четыре, `CLAUDE.md`->Клод точка эм-дэ). Drop any leftover Latin run to a space as a safety net.
- **Stress markers for mis-stressed words.** Silero defaults to a wrong stress on many common words and you MUST force it with `+` placed **before** the stressed vowel: `второй`->`втор+ой` (Silero otherwise reads "вт-о-рой"), `месяц`->`м+есяц`, `уже` (adverb)->`уж+е`, `глаза`->`глаз+а`. Maintain a stress dictionary (stem-based, covers inflections) and extend it whenever a listen reveals a new wrong stress — common offenders are ordinals, homographs (за́мок/замо́к, у́же/уже́), names, and rare words.
- **Verifying a stress marker without listening:** synthesize the word with and without the marker and compare the audio bytes (md5). Identical bytes mean Silero already stresses that syllable (your marker is redundant or misplaced); different bytes mean the marker moved the stress.
- **Pauses — dashes and dotted filenames.** Silero renders an em/en dash (— / –) as a *long* pause; replace them with a hyphen `-` for a short break (measured: em-dash pause ~1.30 s vs hyphen ~1.16 s). Likewise a dotted filename like `CLAUDE.md` voiced as «Клод точка эм-дэ» inserts a heavy pause on «точка» — drop the «точка», use «Клод эм-дэ».
- **EN narration (Kokoro) needs none of this** — it pronounces Latin and numbers in English natively. Normalize the RU text only.
<!-- /allow-non-ascii-block -->
- **Every block is its own sentence — headings AND paragraphs.** Our posts write headings (and some list items / lead lines) WITHOUT a trailing period, so once HTML tags are stripped a block glues onto the next one and the narrator reads them in one breath. The extractor (`extract_lang_text` in `gen-blog-audio.py`) now wraps `<h1-6>` and `<p>/<li>/<blockquote>` in sentinels BEFORE `strip_tags` and, in Python, appends terminal punctuation to any block that lacks `.!?…`: headings get a period **plus a doubled pause** (`. … ` on their own line) so they are set apart; paragraphs get a closing period. This is engine-independent (both Silero and F5 lengthen the gap on consecutive sentence terminators) and applies to RU and EN alike — content tasks do NOT need to hand-punctuate headings. TRAP: the article's main `<h1>` lives inside `<article>` together with the breadcrumb/date; a greedy `<p>(.*?)</p>` regex swallows it into one blob and the title glues onto the lead paragraph. Pull the `<h1>` out FIRST, cut everything up to `</h1>` (hero/nav), and replace `<a>` tags with their TEXT (do not delete — else a CTA like "... at cubrim.com" loses the domain and trails off as "... at .").
- **Cloned author voice (optional, on-device).** A deployment may add the author's own cloned voice alongside the stock Silero/Kokoro voices. It is rendered ON-DEVICE (the author's machine, not the sidecar): RU via OpenVoice v2 (Silero base + tone-color conversion, fast ~30-40 s/article), EN via F5-TTS Base (Apache 2.0, zero-shot from a short reference clip, slow ~45-50 min/article on Apple MPS — batch it). The biometry (speaker embedding + reference WAV and its exact transcript) lives ONLY in a private voice vault referenced by an env var — never in the site repo and never on the CDN; only the finished MP3 is published. The RU text still needs the normalization pass above (the clone runs on top of Silero); the EN text does not. Register it in the manifest under its own voice id like any other voice. The deployment-specific voice id, vault path, and CLI flags are documented in that deployment's own runbook, not here.
- **Semantic fidelity is a hard gate for every TTS engine and voice.** Treat the
  final MP3 as untrusted even when generation exits zero and the file is decodable,
  non-silent, and the expected duration. Freeze and hash the normalized narration;
  transcribe the final MP3 with an independent ASR model in the correct language;
  align source and transcript at paragraph, sentence, and phrase level in reading
  order; and hard-fail every unreviewed missing/reordered paragraph, sentence, or
  meaningful phrase, an inserted sentence, a language mismatch, or an unexpected
  phrase of four or more words repeated at least twice. The alignment report must
  surface every unmatched source/transcript span instead of accepting a paragraph
  because some words matched. Then proof-listen the complete MP3 at normal speed for
  voice identity, pronunciation, repetitions, insertions, omissions, truncation,
  silence, and chunk-boundary glitches. Record reviewer, timestamp, narration hash,
  MP3 hash, and PASS/FAIL. Regeneration invalidates the approval.
- **Failure precedent (2026-07-14).** An EN F5-TTS MP3 repeatedly inserted
  “This recording is part of that same process.” It still passed hash, codec,
  duration, waveform, non-silence, upload, and player checks, and the same bad audio
  propagated into X and LinkedIn videos. Independent ASR plus proof-listening must
  therefore happen before upload or video generation, not after publication.
- **Current enforcement boundary.** Until the publishing application has a
  code-level receipt validator, this is a manual fail-closed preflight. The agent
  must inspect the campaign evidence and must not invoke a publish action when the
  receipt or any PASS verdict is absent. In the Arcanada deployment, the receipt is
  `~/.arcanada-publisher/policy/campaigns/<campaign-id>/evidence/media/<asset-id>/verification.json`
  with sibling `source.txt`, `audio-asr.txt`, `audio-alignment.md`,
  `listening-checklist.md`, and (for MP4) `video-asr.txt`. The receipt requires
  `schemaVersion: 1` plus `campaignId`, `assetId`, `language`, `voice`,
  `sourceSha256`, `audioSha256`, `videoSha256`, `audioAsrVerdict`,
  `listeningVerdict`, `videoAsrVerdict`, `reviewedAt`, and `reviewer`; every
  applicable verdict must be `PASS` (`videoAsrVerdict` may be `NOT_APPLICABLE`
  only when no MP4 exists), and hashes are 64 lowercase hex. This required file
  set and field list is the agent-facing enforcement contract. Publisher's
  `docs/how-to/blog-audio-narration.md` carries the matching operational JSON example;
  verify both committed versions before claiming cross-repository parity. Do not
  claim CLI enforcement until a validator actually ships.
- **Chunking:** keep chunks small (<=600 chars, not the 900 default) — long chunks raise Silero's length-limit 500 even after a split. The chunker self-heals by recursively halving, but small chunks avoid the wasted retry rounds.
- **Cache:** re-voiced MP3s live on Cloudflare R2 with a 1-year `immutable` cache. After overwriting an audio asset you MUST purge the Cloudflare cache for those URLs (and the listener should hard-refresh the browser), or the old narration keeps playing. Same rule as any content edit — see § Website Publishing.

**Telegram first-comment — one link, the article in the post's language.** On a Telegram channel post, the comment links to the full article in the **same language as the post** — a single URL, nothing else. Do NOT add the other-language version (an RU post links the RU article only, not the EN one), and do NOT link the channel itself — the reader is already in it. This is narrower than the multi-link FB/LinkedIn comment; keep the TG comment minimal.

**X (EN) first-comment — the EN article + the canonical Telegram (RU) post.**
On an X post the first reply carries TWO links, each language-labelled: the full
EN article (`blog (EN)`) and the canonical Telegram (RU) channel post (`Telegram (RU)`).
The RU Telegram post already exists at this point (TG is published before X per
§ Publication Order), so its URL is available. This is wider than the single-link
Telegram comment and narrower than the FB/LI comment (no X-self link, since we ARE
on X). Contextual links inside the post body (sources, prior article, standards
bodies) are fine and are NOT the CTA block — only the CTA cross-links move to the
first comment (see § Universal rule).

**FB / LinkedIn / VK first-comment — must cross-link both Telegram (RU) and X (EN).** Because these are published **after** TG and X (see § Publication Order), their first comment carries the blog link in the platform's language **+ the canonical Telegram (RU) post link + the X (EN) post link** (plus the product/framework site link for product articles). Label the language on each link (`Telegram (RU)`, `X (EN)`, blog `(RU)`/`(EN)`) so the reader knows the destination language before clicking. This is the reason X is published before FB/LI/VK — those URLs must already exist when their comments are written. All cross-links go in ONE comment; do not post a second comment to add a link.

<!-- gate:history-allowed -->
**Retrofit tools (FB):** the consolidated publishing app's Facebook adapter provides post-edit (remove a links-block from an existing post body) and comment-edit/replace (rewrite an existing first-comment) operations. In the Arcanada deployment that is the Publisher (`Projects/Publisher/code/arcanada-publisher`, `edit` / `comment` sub-commands). The standalone `fb-publish` retrofit scripts were retired once their capability was absorbed.
<!-- /gate:history-allowed -->

### LinkedIn

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 3000 chars | No HTML, no Markdown |
| Article title | 100 chars | Plain text |
| Article body | 110,000 chars | Rich text (via editor) |
| Comment | 1250 chars | Plain text |

**Formatting**: Line breaks preserved. No bold/italic/links in post text via API — use Unicode bold (𝗯𝗼𝗹𝗱) if needed, but sparingly. Hashtags at the end. Links in text trigger preview card.
**Images**: 1200×627 px optimal for link previews. Max 9 images per post.
**Video**: Max 10 min, 5 GB. Native upload gets better reach than YouTube links.

#### Manual browser publishing via Claude-in-Chrome (no publisher script)

When the publishing app is unavailable and you must drive the post by hand through the browser-automation tools (an exceptional fallback — the mandate is to fix the app, not route around it), several failure modes recur. Each has a deterministic workaround — apply it preemptively, do not rediscover it per session.

1. **Media via clipboard FIRST, then text — NEVER the file-picker (mandatory, all browser composers).** ALL media (image OR video) AND the post text are attached **through the OS clipboard (paste)**, media first, then text. Put the file on the clipboard (`osascript -e 'set the clipboard to (POSIX file "/path/media.mp4")'` on macOS), open the composer, paste (Cmd/Ctrl+V), and **wait for the upload to finish** before typing. Then paste the text. Do **NOT** use the `Photo`/`Add media`/`Upload from computer` affordance or `file_upload`/`setInputFiles`: host filesystem paths are rejected, the OS picker is invisible to automation, and it is unreliable — this is the only sanctioned attach method (operator rule, reaffirmed 2026-06-26). If text was already typed into a media-less composer, clear it and restart media-first rather than retrofitting media around the text. (LinkedIn caveat: the `<video>` preview appears right after paste, but the real upload runs in the background **after** you click «Post» — do not tear down the browser until the upload bar hits 100% **and** a few seconds more, or the post publishes video-less.)

2. **Multi-line comment paste flattens to the last line (LinkedIn).** Pasting a 3-line link block into the LinkedIn comment field via Cmd+V silently keeps only the **last** line. Do not trust a single paste. Instead type each line and insert line breaks with **Shift+Enter** (a bare Enter SUBMITS the comment on LinkedIn). Verify the field's `innerText` contains all lines before clicking `Comment`. When editing an existing comment, LinkedIn renders TWO contenteditable boxes (empty new-comment + the edit box) — select the edit box **by content**, not `.first()`, type (don't paste) the change, and re-read it to confirm the final text BEFORE clicking Save.

**Post text via clipboard, not character-typing.** For long post bodies, `cat <file> | pbcopy` then Cmd+V is instant; a `type` action of ~10k chars times out at the CDP 30s limit (the text still lands, but the action reports failure). Clipboard paste of the post BODY works on every platform; only the LinkedIn comment field has the line-flattening quirk above.

**Verify text and approved media before the irreversible Publish click, and re-verify the rendered post after.** A partial publish (media attached, text missing — or vice-versa) leaves a broken public post that cannot be fixed by retry without producing duplicates. Snapshot the composer (body present AND media preview present) before Publish. For narration-backed video, verify that the attached file hash matches the MP4 in the approved audio/video receipt; a visible preview proves attachment, not semantic correctness. Open the published post afterward and confirm both text and media are there. On a timeout/modal error, check the profile for a partial publish BEFORE assuming nothing was posted.


### Facebook

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 63,206 chars | No HTML, no Markdown |
| Comment | 8,000 chars | Plain text |
| Link description | 500 chars | Via OG tags |

**Formatting**: Line breaks and emoji supported. No rich text in posts via API. Links generate preview cards from OG tags.
**Images**: 1200×630 px for shared images. Max 10 per post.
**Video**: Max 240 min, 10 GB.

### X / Twitter

| Field | Max length | Formatting |
|-------|-----------|------------|
| Tweet | 280 chars (free) / 25,000 (any Premium tier) | No HTML, no Markdown |
| Thread | Unlimited tweets | Each ≤280/25,000 |
| DM | 10,000 chars | Plain text |
| Alt-text (per image) | ~1,000 chars | Plain text — separate budget |

**Premium character limit (the Arcanada accounts are Premium):** the long-post limit is **25,000 characters** and it is the **same across every Premium tier — Basic, Premium, Premium+**. Do not gate it on Premium+ only, and do not say "Premium+" when the rule is just "Premium". A free (non-Premium) account is still capped at 280.

**Attaching media does NOT reduce the character budget.** A photo, video, GIF, or poll leaves the full 25,000-char text limit intact — media does not eat into the count. So on a Premium account, prefer the full post text in the tweet body (with the image attached) over a 280-char teaser, unless brevity is the deliberate goal. The teaser-plus-link pattern is a *free-account* constraint, not a Premium one.

**Reach/UX nuances:** posts over 280 chars render in the feed collapsed behind a "Show more" link — so still front-load the hook in the first ~280 chars. The 25,000 limit applies identically to original posts and to replies/quotes. Alt-text has its own ~1,000-char budget that does not touch the main text count.

**Formatting**: No rich text. Links count as 23 chars (t.co wrapping). Up to 4 images, 1 video, or 1 GIF per tweet.
**Images**: 1600×900 px optimal. Max 5 MB (JPG/PNG), 15 MB (GIF).
**Video**: Max 2:20 (free) / 60 min (Premium), 512 MB.

**Premium UI is NOT the API — two separate products (verified 2026-06-05):**
- **X Premium subscription** (~$8/mo Premium, ~$16/mo Premium+) unlocks *in-app/in-browser* features: 25,000-char long posts, Articles editor, analytics, reply-boost. It grants **no API access**. Our accounts (e.g. `@VeritasArcanaAI`) are Premium → publish via the **web UI** (manual or browser automation), not the API.
- **X API** (programmatic posting) is a *separate paid product*. As of Feb 2026 the free/Basic/Pro tiers are closed to new signups — default is **pay-per-use**: ~$0.015 per standard post, **~$0.20 per post containing a URL** (link posts are 13× the price), 2M reads/mo cap before Enterprise. So API auto-posting of link-bearing announcements is expensive; the UI route (Premium, no per-post cost) is preferred for our volume.

**X Articles** (long-form editor, `x.com/compose/articles`): since Jan 2026 available to **all Premium tiers** (was Premium+ only). Up to **100,000 chars**, rich formatting (headings, bold/italic/strikethrough, lists, indentation), embeds images/video/GIF/posts/links. Desktop-web only; lands in a dedicated "Articles" tab on the profile + in follower timelines. **Caveat — reach:** Articles often behave like external links algorithmically (click-through friction) and may get *less* distribution than a native long post. For announcing a blog article, a native long post (≤25K, image attached, hook in first 280) usually out-reaches an X Article. Use Articles only when the X-native long-form artefact itself is the goal.

### VK

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 15,895 chars | Limited HTML via API |
| Comment | 4,096 chars | Plain text |

**Formatting**: API supports `<b>`, `<i>`, `<a>`. Line breaks preserved. Hashtags work.
**Images**: Up to 10 per post. Optimal 1200×800 px.
**Video**: Upload or link from external services.

### Instagram

| Field | Max length | Formatting |
|-------|-----------|------------|
| Caption | 2,200 chars | No HTML, no Markdown |
| Comment | 2,200 chars | Plain text |
| Bio | 150 chars | Plain text |
| Story text | ~200 chars | Overlay |

**Formatting**: Line breaks via mobile only (or Unicode line break `\n` via API). No clickable links in captions (only in bio and stories with 10K+ followers or link sticker).
**Images**: 1080×1080 (square), 1080×1350 (portrait), 1080×566 (landscape). Max 10 per carousel.
**Video/Reels**: Max 90 sec (Reels), 60 sec (feed), 15 sec (stories). Max 650 MB.
**Hashtags**: Max 30 per post, 10–15 recommended.

---

## Website Publishing

### OG Tags (Open Graph)

Required for proper link previews on all social platforms:

```html
<meta property="og:title" content="Title — max 60 chars">
<meta property="og:description" content="Description — 120-160 chars">
<meta property="og:image" content="https://example.com/img/og.png">
<meta property="og:url" content="https://example.com/page">
<meta property="og:type" content="article">
<meta property="og:locale" content="ru_RU">
```

**OG image**: 1200×630 px, PNG or JPG, <5 MB. Text on image should be readable at thumbnail size.

### Twitter Card Tags

```html
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Title">
<meta name="twitter:description" content="Description">
<meta name="twitter:image" content="https://example.com/img/og.png">
```

### Blog Post Technical Checklist

- [ ] URL is slug-friendly (`/blog/my-post-title`, not `/blog/123`)
- [ ] `<title>` and `<meta description>` are unique and within limits
- [ ] OG tags and Twitter Card tags present
- [ ] `<link rel="canonical">` set
- [ ] Heading hierarchy correct (one `<h1>`, logical `<h2>`→`<h3>`)
- [ ] Images have `alt` text, are optimized (<200 KB), use modern formats (WebP)
- [ ] Internal links use relative paths or full URLs consistently
- [ ] Multi-language: `<link rel="alternate" hreflang="ru">` if applicable
- [ ] RSS feed updated (if exists)
- [ ] Sitemap regenerated (if static)
- [ ] Audio narration (if the blog has a player): RU text normalized before Silero TTS — numbers→words, Latin→Cyrillic, stress markers on mis-stressed words; every heading AND paragraph ends a sentence (extractor adds the period; headings get a doubled pause) so blocks do not glue together; the author's cloned voice available as an option if the deployment provides one (see § Blog audio narration); MP3s uploaded to R2 AND Cloudflare cache purged for the audio URLs
- [ ] Every final narration MP3 has a content-verification receipt bound to the
      frozen narration and MP3 hashes: correct-language independent ASR comparison,
      no unreviewed missing/reordered paragraph, sentence, or meaningful phrase and
      no unexpected repeated insertion, plus complete proof-listening with
      reviewer/timestamp/PASS. Every derived MP4 records that approved MP3 hash and
      passes the same final-audio transcript check after muxing.

---

## Multi-Platform Workflow

### Adapting One Post for Multiple Platforms

1. **Start from the longest version** (Telegram/Facebook — most text capacity)
2. **Adapt down** for constrained platforms:
   - LinkedIn: trim to 3000, remove HTML formatting, add hashtags
   - X/Twitter: extract the hook + link, or create a thread
   - Instagram: rewrite as caption, prepare a visual
   - VK: similar to Facebook, adjust formatting

### Platform-Specific Patterns

| Pattern | Telegram | LinkedIn | Facebook | X | VK | Instagram |
|---------|----------|----------|----------|---|-----|-----------|
| Links clickable in text | Yes | Yes | Yes | Yes (shortened) | Yes | No (bio only) |
| Hashtags useful | Moderate | Yes | Low | Yes | Yes | Yes (max 30) |
| Line breaks preserved | Yes | Yes | Yes | Yes | Yes | Via API only |
| Rich text | HTML subset | No | No | No | HTML subset | No |
| Link preview card | Yes | Yes | Yes | Yes | Yes | No |
| Best post length | 500-2000 chars | 1000-2000 chars | 500-3000 chars | hook in first 280, up to 25K (Premium) | 500-2000 chars | 500-1500 chars |

### Publication Order (FIXED — not just "for reach")

The platform order is a **hard contract**, not a reach heuristic. Publish in this exact sequence:

1. **Website/blog** first (RU+EN; canonical URL, SEO indexing starts). Capture both URLs.
2. **Telegram** (RU canonical, instant delivery). Capture `t.me/<channel>/<msg_id>`.
3. **X/Twitter** (EN premium full-article). Capture `x.com/<handle>/status/<id>`.
4. **Facebook / LinkedIn / VK** (in any order among themselves) — all **after** X.
5. **Instagram** (last — requires the most visual adaptation), when in scope.

**Why X comes before FB/LinkedIn/VK (do not reorder).** The FB / LinkedIn / VK first
comments must cross-link **both** the canonical **Telegram (RU)** post **and** the **X (EN)**
post. Those two URLs only exist once TG and X are already published — so TG and X go first,
and X is published **before** FB/LI/VK, not alongside or after them. Publishing FB/LI/VK
before X forces a second pass to back-fill the X link into their comments (a recurring
"missing X link in the FB/LI comment" regression). The full per-platform first-comment
contract lives in `Projects/Publisher/code/arcanada-publisher/documentation/explanation/social-links-and-comments-policy.md`.

---

## Testing and Verification

1. **Always test before publishing** — send to a private chat/draft/staging first
2. **Check link previews** — after posting a URL, verify OG card renders correctly
3. **Verify formatting** — HTML tags rendered, not shown as raw text
4. **Check image display** — cropping, resolution, text readability at thumbnail size
5. **Test on mobile** — most social media consumption is mobile
6. **OG cache busting** — platforms cache previews; after updating OG tags:
   - Facebook: use Sharing Debugger (`developers.facebook.com/tools/debug/`)
   - LinkedIn: use Post Inspector (`linkedin.com/post-inspector/`)
   - Telegram: send link to @webpagebot or re-send with `?v=2` query param
   - X/Twitter: use Card Validator

---

## DOM-Automation Selector Discipline

When automating against opaque third-party DOMs (Facebook, X/Twitter, LinkedIn, Instagram, Gmail web, or any UI not under our control), default to **exact aria-name selectors** for action buttons — Publish, Submit, Delete, Confirm, Send.

Reserve substring matching for personalized prompts (composer prompts that embed the user's name, greetings, or other per-account text that cannot be matched exactly).

**Why.** Substring match on an action-button label has produced silent wrong-element clicks in adjacent compound labels — e.g. a short localized "Publish" label matching inside an unrelated, longer compound label such as "Schedule settings — Publish now" and clicking the wrong button. An exact match on the action label fails loudly (selector not found) instead of silently clicking a neighbor.

Source: a prior reflection Class A proposal (NS2).

---

## Recurring-mistakes pre-publish checklist

Run through this checklist before every publish action. Each item consolidates
a recurring mistake identified across publishing tasks. This is a hard gate —
if any item fails, fix it before publishing.

### Voice and authorship

- [ ] No phantom "we" — solo-founder content uses impersonal voice or
  product-as-subject, never plural first-person (neither "we did X" nor
  implicit plural past tense: "обнаружили / починили / повесили"). <!-- allow-non-ascii: russian-phantom-we-verb-form-example -->
- [ ] Not written via an external writing assistant — voice-bearing content
  is generated by the assigned model, not delegated. Check the writing
  pipeline; if `coworker write` was used for the draft, rewrite natively.
- [ ] No moralizing or instructional tone — state facts and outcomes;
  never prescribe how others should work.

### Factual accuracy

- [ ] All numeric claims (stats, counts, dates, prices, rates) verified from
  primary sources or direct measurement — not estimated, not from memory.
- [ ] Model/product names are current: if the content names an AI model or
  product version, confirm it is still the canonical current version before
  publishing (e.g. DeepSeek version, Claude model ID).
- [ ] No "Aether" named in public content — replace with "primary work" or
  omit the reference entirely.

### Technical correctness

- [ ] Links are live and resolve correctly. Test each URL in a browser tab.
- [ ] Code snippets are copy-paste safe — no invisible Unicode, no smart quotes
  replacing ASCII quotes, no line-wrap artefacts.

### Platform compliance

- [ ] Text length within platform limit (check per-platform table in
  `## Platform Limits` above).
- [ ] No raw HTML visible in plain-text platforms (LinkedIn, Facebook, X).
- [ ] Images sized for the target platform; no text unreadable at thumbnail.
- [ ] For Telegram: length measured in UTF-16 code units, not characters.

### Publish order + cross-links + back-link gate (multi-platform)

- [ ] Published in the FIXED order — site → Telegram (RU canonical) → X (EN) →
  Facebook / LinkedIn / VK. X goes BEFORE FB/LI/VK so its URL exists for their
  comments (see § Publication Order). Reordering is a defect.
- [ ] FB / LinkedIn / VK first comment carries BOTH the Telegram (RU) link AND
  the X (EN) link (plus the blog link in the platform language, plus the product
  site for product/framework articles), all in ONE comment.
- [ ] CLOSING GATE — the blog article's `social` back-link block is present on
  RU+EN, points at the real permalinks, and is verified live. An article live
  with social posts but no/incomplete `social` block is an incomplete publish;
  the task does not close without it.
- [ ] Each back-link permalink in the `social` block was OPENED IN A BROWSER and
  confirmed to render OUR post of THIS cycle (title/lead match, correct author,
  publish date) BEFORE it was written into the article and deployed. Do not trust
  a URL from a prepared `*-parent-url.txt`, from memory, from a `curl` HTTP 200
  (FB/LI/X return 200 for a wrong/deleted/"not found" post too), or from a
  first-line-of-file match. Do not hand-reconstruct FB `pfbid` / LinkedIn share
  URLs — copy the working permalink verbatim (LinkedIn:
  `posts/<vanity>_<slug>-share-<id>-<code>/`, NOT `feed/update/urn:li:activity:<id>/`;
  Facebook: strip the `?__cft__=…&__tn__=…` tail). Deploy, then re-check the live
  RU+EN pages that the hrefs shipped.
- [ ] Post video uses the animated-cover cycle; when narration audio exists it
  carries the bottom audio-amplitude strip (default-on). A bare full-frame
  waveform as the whole video is forbidden (see § Video standard).
- [ ] Narration content itself is approved: the exact final MP3 and muxed MP4
  passed correct-language ASR comparison against the frozen source, complete
  proof-listening, and hash-bound evidence. Duration, codec, waveform, and a
  visible player are not substitutes.
- [ ] The operator has not been promised an automatic repair path that the
  platform does not support. Every attached image/video is treated as immutable
  after publish unless the adapter documents and tests exact replacement; X,
  LinkedIn, and Facebook have no such general replacement path in this workflow.
  Any discovered live defect freezes delete/edit/re-publish/comment actions until
  the operator explicitly authorizes each named platform and URL.

### Multi-vendor consilium post-publish

If content was produced via `--consilium` multi-vendor mode:

- [ ] `judge-decision.md` exists in the run directory and records the selected slot.
- [ ] `final.md` is the file being published — not one of the raw `draft-*.md` files.
- [ ] If degradation occurred (`degradation_note.txt` present), the operator has
  acknowledged the reduced vendor count before publishing.

### Multi-vendor execution mode — interactive tmux only

The multi-vendor fan-out runs each vendor as an **interactive tmux pane** and
delivers the brief via the pane (the `run_vendor_tmux` path). It MUST NOT run
the vendor CLIs in headless / print mode (`-p` / `exec` / `--print`).

- [ ] Vendor agents run in interactive panes, not headless. Subscription-based
  CLIs are authenticated in their interactive TUI; headless mode requires a
  separate per-vendor API key (API-billing), which is out of scope for a
  subscription-only setup — one vendor CLI rejects headless invocation outright
  even where it is interactively signed in.
- [ ] The brief is sent to each pane and the reply is captured after the pane
  goes idle — never piped to a non-interactive subprocess.
- [ ] Direct-subprocess / test-mode execution is reserved for the test suite
  only; it is never the path for a live content run.

The orchestrator pane and the vendor panes run with **different contexts**:

- [ ] The **orchestrator** pane (the pane that drives the run, judges drafts,
  and synthesises the final) runs as a full framework agent — it uses the
  framework rules and the delegation tooling.
- [ ] The **vendor** panes (the per-vendor draft authors) run as **bare agents**
  with **no framework context**. The orchestrator/operator sends them the raw
  content brief directly through the pane — no framework commands, no skills,
  no project instruction file in their working context. The goal is each
  vendor's **native voice** on the same brief; loading framework context into a
  vendor pane contaminates the voice comparison and is a defect.
