# iptvidn streams resolved on-click via HTTP

iptvidn channels have no stable playable URL: every play needs a per-slug
Flussonic secure-link token (~3 h lifetime) and the serving host rotates per
channel. We store each channel as an `iptvidn://<slug>` **channel reference** and
**resolve** it on demand at play time — a single plain HTTP GET to
`http://iptvidn.com/play.php?stream=<slug>` returns an iframe whose `src` carries
both host and token as plain text, from which we build
`http://<host>/<slug>/index.m3u8?token=<token>` and hand that to the player.
Resolution runs at the single `Media()` call site. Failure handling depends on
whether the channel had already started playing:

- **Never played** (resolve or first open fails) → treat as a dead channel and
  auto-skip to the next one, reusing the existing watchdog path.
- **Played, then failed** (almost always token expiry mid-watch) → **re-resolve
  the same slug** with a fresh token and reopen; only fall back to auto-skip if
  that re-resolution also fails.

## Considered Options

- **Webview to obtain the token** (their own site embeds a JS player that needs
  one). Rejected: the token is rendered *server-side as plain text* by
  `play.php`; no JavaScript execution is required, so the existing `HttpClient`
  + a regex suffices. A webview would add a heavyweight dependency for nothing.
- **Cron / background pre-fetch of tokens.** Rejected: it would have to refresh
  126 short-lived tokens every <3 h in the background, where Android TV
  aggressively kills background work — versus one ~244-byte GET on click that is
  always fresh.

## Consequences

- The host and token are never persisted; only the slug is stable. A removed or
  dead slug simply 403s on play and auto-skips.
- Each play incurs one extra HTTP round-trip before buffering. No cache in v1
  (HLS buffering dominates the latency); an in-memory `slug → (url, expiry)`
  cache can be added later if zapping feels slow.
- Tokens carry an absolute ~3 h expiry, so a continuous watch can outlive one.
  This is handled per-session, never by a background cron: reactively
  (re-resolve the current channel when it fails after having played) and
  proactively (a single timer for the *active* channel re-resolves ~60 s before
  the token's embedded expiry and reopens cleanly, avoiding an error flash).
  The timer is scoped to the one playing channel only — not a poll over all 126.
