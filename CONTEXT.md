# Kivo

IPTV launcher for Android TV: a hardcoded set of playlists whose channels are
browsed, favourited, and played full-screen on a TV remote.

## Language

### Channels & playback

**Channel reference**:
The stable string that identifies a channel and is stored as its `url`. Used as
the key for favourites and watch history. It is either a directly-playable
address or a scheme-prefixed reference that must be resolved first.
_Avoid_: stream URL, link.

**Direct channel**:
A channel whose reference is itself the playable address (static M3U sources).

**Resolvable channel**:
A channel whose reference must be turned into a playable URL at play time
(e.g. iptvidn, referenced as `iptvidn://<slug>`).
_Avoid_: tokenized channel.

**Stream resolution**:
Turning a channel reference into a currently-playable URL, on demand, at the
moment of playback.
_Avoid_: token fetch, refresh.

**Resolver**:
The component that performs stream resolution for a given reference scheme.

### iptvidn source

**Slug**:
iptvidn's stable per-channel identifier, e.g. `STAR-SPORTS-1`. The slug is the
only stable part of an iptvidn channel; its host and token rotate.

**Stream token**:
The short-lived (~3 hour) Flussonic secure-link credential carried in the
`token` query parameter of a resolved iptvidn URL. Per-slug, not global.
_Avoid_: key, auth, signature.
