# Privacy and media adapters

`dartitect_privacy` is an iOS ATT status/request boundary. Construction and
status reads are prompt-free; only a consumer-owned interaction calls
`request()`. Preserve every native state, return typed not-supported outcomes
without channel calls elsewhere, emit no telemetry, and keep disclosure text,
usage descriptions, request timing, analytics policy, and legal review in the
application.

`dartitect_media` saves one consumer-selected image on Android or iOS. Status
reads and `saveImage` never request permission. The consumer owns source-file
lifetime, album naming, UX, and legal/platform review. The plugin owns only
request coordination and its Android legacy-request history bit. Await
`clearOwnedState()` before package removal; a cleanup failure blocks a
zero-residue claim. Never log paths, names, bytes, albums, native messages, or
receipts. Test unsupported hosts without channel calls and supported hosts
through the real method-channel/native lifecycle boundary.
