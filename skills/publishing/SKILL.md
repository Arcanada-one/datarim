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

## Universal rule — links go in the first comment, not the body

For **all** social platforms (FB, LinkedIn, Telegram, VK, Twitter/X threads, etc.) the **post body must not contain a standalone "links block"** — a section header like `Куда смотреть` / `Ссылки` / `Resources` / `Полезное` followed by a bullet-list of URLs is forbidden in the body. All such CTA-links (blog URL, dashboards, repositories, doc cross-refs) MUST be published as the **author's first comment** under the post. <!-- allow-non-ascii: literal-russian-section-headers-fixture-for-publishing-rule -->

Rationale:
- **FB & LinkedIn algorithms** downrank posts that contain external links in the body — comment-level links bypass that penalty.
- **Reader UX** — the post body ends on a narrative beat; the link list lives in a single canonical place (the pinned/top comment).
- **Maintenance** — one comment to update if a URL changes, vs editing the rendered post (FB edit history is shown to readers).

Inline mentions in prose are fine (`Datarim (github.com/Arcanada-one/datarim, MIT) is open-source`, `Munera on muneral.com`). The rule targets **standalone link sections**, not contextual references.

Publisher pattern: immediately after `POST_URL` is captured, post the first-comment with the CTA-links block. On FB and LinkedIn that is a normal `Прокомментировать` action under the post; on Telegram it is the discussion-thread comment under the channel post (see canonical recipe above). If the platform's comment size is smaller than the link list, keep blog URL + 2–3 anchor links and rely on the website (`arcanada.one`) for the full directory. <!-- allow-non-ascii: literal-russian-fb-action-token-required-for-publisher-pattern -->

**Attach the hero image to image-capable posts.** When the post promotes an article that has a hero image, attach that image to the post itself — FB `--image-file`, LinkedIn `--image-file`, TG `sendPhoto`. A bare text post with no image loses badly in the feed, and an article's OG-preview from a *comment* link is not a substitute (the body shows no image). A FB post published text-only loses badly in the feed — there is no way to add media retroactively (UI edit replaces text only), so you must delete and re-publish, then re-add the first comment. Get the image right on the first publish.

**Video standard for social posts — animated cover (cover → cycling effects) over the article narration.** When a post has both a cover image AND article narration audio, the preferred attachment is NOT a static cover and NOT a plain cover+audio MP4, but an **animated screensaver video**: the post's cover shown clean for ~2 s, then a NEW visual effect every ~3 s cycling through a large randomly-shuffled pool, with smooth crossfades (~0.6 s) between effects, for the full length of the narration. The canonical generator is `Projects/Publisher/code/arcanada-publisher/dev-tools/video/make-cycle-video.sh <cover> <audio> <out.mp4> [intro_sec] [seg_sec] [seed]` — pure ffmpeg, no plugins. Rules:
- Inputs come **from the post itself**: the cover is the article's hero cover (the post-level cover, not an in-article inline preview), the audio is the article's own narration in the post language. The intro frame is always that cover.
- The effect order is **re-shuffled randomly every run** (Fisher-Yates over the pool) so two posts never get the same sequence; pass a fixed `seed` only to reproduce one.
- Video length always equals the narration length; narration plays from t=0 (the 2 s intro is the cover held still, not silence).
- **No audio?** Fall back to a ~30 s clip from the cover alone (the generator's no-audio path), still with cycling effects.
- Do NOT use bare audio-waveform visualizers (showwaves/showcqt/showspectrum) as the post video — they look generic; the animated-cover cycle is the house style.
- Per-platform attach: X long-form and LinkedIn take the MP4; Facebook feed forces video into Reels, so on FB use the static cover image instead (keep the video for X and LinkedIn); Telegram can take the MP4 via `sendVideo`.

**Telegram first-comment — one link, the article in the post's language.** On a Telegram channel post, the comment links to the full article in the **same language as the post** — a single URL, nothing else. Do NOT add the other-language version (an RU post links the RU article only, not the EN one), and do NOT link the channel itself — the reader is already in it. This is narrower than the multi-link FB/LinkedIn comment; keep the TG comment minimal.

<!-- gate:history-allowed -->
**Retrofit tools (FB):** `Projects/FB Publish/code/fb-publish/bin/fb-edit-post.sh` removes a links-block from an existing post body; `bin/fb-edit-comment.sh --match-prefix <text>` rewrites an existing first-comment to extend the link list. Verified working 2026-05-20 on CONTENT-0050.
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

When the `fb-publish` / `li-publish` / Publisher scripts are unavailable and you drive the post by hand through the browser-automation tools, three failure modes recur. Each has a deterministic workaround — apply it preemptively, do not rediscover it per session.

1. **Image FIRST, then text (LinkedIn + Facebook).** Open the composer with the **Photo** affordance so the media editor (`Select files to begin`) opens before any text exists. Typing text first collapses the media affordance and the file input is never created. (Already canonical for the publisher adapters; it applies identically to the manual path.)

2. **Image upload is the hard blocker — have the operator insert it.** The `file_upload` tool rejects host filesystem paths, the OS picker is invisible to automation, clipboard-paste of an image is accepted by X but NOT by LinkedIn, and a cross-origin `fetch` of the cover is blocked by the site CSP. The reliable path is to open the composer in media-upload mode, then ask the operator to click `Upload from computer` and pick the file themselves (the picker is visible to them). Surface the absolute cover path so they can paste it. Resume — set text — once they confirm the image is attached.

3. **Multi-line comment paste flattens to the last line (LinkedIn).** Pasting a 3-line link block into the LinkedIn comment field via Cmd+V silently keeps only the **last** line. Do not trust a single paste. Instead type each line and insert line breaks with **Shift+Enter** (a bare Enter SUBMITS the comment on LinkedIn). Verify the field's `innerText` contains all lines before clicking `Comment`.

**Post text via clipboard, not character-typing.** For long post bodies, `cat <file> | pbcopy` then Cmd+V is instant; a `type` action of ~10k chars times out at the CDP 30s limit (the text still lands, but the action reports failure). Clipboard paste of the post BODY works on every platform; only the LinkedIn comment field has the line-flattening quirk above.

**Verify both text and image before the irreversible Publish click, and re-verify the rendered post after.** A partial publish (image attached, text missing — or vice-versa) leaves a broken public post that cannot be fixed by retry without producing duplicates. Snapshot the composer (body present AND image preview present) before Publish; open the published post afterward and confirm both are there. On a timeout/modal error, check the profile for a partial publish BEFORE assuming nothing was posted.


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

### Publication Order

Recommended sequence for maximum reach:
1. **Website/blog** first (canonical URL, SEO indexing starts)
2. **Telegram** (instant delivery to subscribers)
3. **LinkedIn** (professional audience, slower feed)
4. **Facebook** (broad audience)
5. **X/Twitter** (hook + link to full post)
6. **VK** (if relevant audience)
7. **Instagram** (requires visual, last because most adaptation needed)

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
