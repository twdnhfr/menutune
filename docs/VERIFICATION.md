# Verification of the first version

As of 11 September 2026, locally on Apple Silicon with macOS 26.6.2. The minimum target is macOS 14; older macOS versions were not exercised separately.

## Automated tests

`swift test`: **28 tests, 0 failures**.

Covered are URL and time parameters, accepted hosts, clipboard link detection, queue navigation and repeat, removal and reordering, atomic storage and the handling of damaged files. One test drives the real AppModel with a private named pasteboard and a temporary library: reading alone changes neither playback nor queue, confirming adds exactly once, dismissing stays effective for the same clipboard generation, and new clipboard content is examined afresh. The general pasteboard is never touched by the test.

One test hosts the interface in a real window and checks that the measured content height follows the layout and grows when the queue is expanded. The popover height is therefore no longer a hand-kept copy of the layout.

Three tests guard the uniqueness of the queue: a known video creates no second entry and returns the existing one, the input field says so instead of staying silent, and an older library holding duplicates is merged on load, with a selection pointing at the dropped copy moved to the surviving entry. Counter-check: removing either the check on append or the merge on load fails three tests each.

Further tests came out of the review on 11 September 2026. A library with an unknown repeat mode and a missing title stays readable instead of failing the whole load. A link that is already queued keeps the title already fetched. The guarantee the README makes for a damaged file is now checked end to end: the warning appears, work continues in memory, and the file on disk stays byte for byte what it was. Moving an entry down is covered for the first time, as are removing an entry that is not selected, removing the current last entry, stepping back from the first track without repeat, and both operations on an empty queue. The clipboard length limit is now hit by a link that is valid apart from its length, rather than a string that was never a URL.

Two tests cover the pointer prediction of the avoidance logic, once as the only reason a move happens and once as the only reason a candidate is rejected. Counter-check: neutralising the prediction in the source fails exactly those two and nothing else. The former test named after a stationary pointer never checked the cooldown, only the proximity guard, and is now named after that.

The unit tests no longer reach youtube.com. Every AppModel used to pull the iframe API into a real web view, and accepting a clipboard suggestion resolved the title over the network. Both paths now hang off a single flag in the initialiser that only the tests turn off.

Nine tests cover the avoidance logic in total: approach, the order of safe targets, movement prediction in both directions, a pointer left behind after a move, the cooldown, the absence of safe targets, and negative screen coordinates. A regression test checks the swing through the middle in both directions, bottom to middle to top to middle to bottom. A host test makes sure a late removal from the old SwiftUI container does not remove a web view that has already moved into the floating window. The storage test covers all three sizes as well as older libraries without a size entry.

## Test against the real YouTube player

Video: `https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s`

Successful run on 11 September 2026, 09:50–09:52 UTC, in the **notarised release bundle** and therefore in exactly the state that ships. It also covers the review fixes from the same day:

| Check | Result |
| --- | --- |
| Start with a time parameter | playback from about second 3 |
| 30 seconds with the popover closed | time keeps running, all six samples invisible and playing |
| Reopening | playback is preserved |
| Pause and resume | time holds while paused; the status switches yellow and green |
| Automatic track change with the popover closed | the next queue entry starts |
| Replay through the embedded player after the queue ended | status and time stay in sync |
| Simulated network failure, then a queue selection | the player reloads and plays |
| Simulated process failure, dismiss the message, play | the player reloads and plays |
| Volume change inside the web player | is taken over into the AppModel |

The closing line from `build/playback-final-smoke.log`:

```text
SMOKE PASS: hidden=true pause=true resume=true automaticNext=true embeddedReplay=true recovery=true dismissedRecovery=true nativeVolume=true
```

Six samples with the popover closed consistently show `visible=false playing=true indicator=playing` with the time advancing. The status dot now survives buffering, and pause reports `indicator=paused` where it briefly reported `idle` before.

The test evaluates YouTube's state messages and progress. WebKit's media state is logged alongside. Measuring actual sound from speakers or headphones is not part of it.

The test needs an interactive desktop session. In a non-interactive shell the popover never appears and the sequence never starts; the menu bar icon has to be clicked once.

Two fixes from 11 September 2026 are **not** covered by that run because it never triggers them: skipping a video the embed refuses, and picking up a YouTube recommendation started inside the player. Both need video material the test does not use.

## The shipped app bundle

Checked on 11 September 2026: with the `.build` directory hidden, the bundle starts cleanly and the player reports `ready`. Before the fix the same attempt aborted immediately with `Fatal error: could not load resource bundle`, because SwiftPM's `Bundle.module` looks only next to the executable and then at a hardcoded build path. `codesign --verify --strict` still passes.

## The release path

`scripts/release.sh` ran end to end on 11 September 2026, including notarisation with Apple. Both submissions were accepted; the app and the disk image each carry their ticket.

| Check | Result |
| --- | --- |
| Universal build | `x86_64 arm64` |
| Signature | Developer ID, hardened runtime, secure timestamp |
| Entitlements | none required; the app starts and the player reports `ready` |
| Notarisation of the app | accepted, ticket stapled |
| Notarisation of the disk image | accepted, ticket stapled |
| Download carrying the quarantine flag | Gatekeeper: `accepted, source=Notarized Developer ID` |
| App dragged out of the image | accepted, ticket travels with the copy, starts |

The counter-check reproduced the download: quarantine attribute set on the image, mounted, app copied out, verified and started. That is exactly the path a website visitor takes. This closes the earlier state in which both the older DMGs under `build/production` and every local build were unnotarised and therefore rejected by Gatekeeper.

The script's preflight checks exit with status 1 before anything is built: an unclean working tree without `--allow-dirty`, and a missing or unusable notarytool profile.

## Manual checks

- The running native interface was inspected visually.
- The video uses the full width along the top edge; separate playback controls were removed.
- Track actions are reachable solely through the native menu arrow; opening that menu was exercised.
- A normal restart preserves both saved tracks, shows the selected video without autoplay, and allows a direct start through the embedded player.
- The global shortcut `⌘⇧Y` was added for opening and closing. The user confirmed it explicitly on their own keyboard on 10 September 2026. Shortcut behaviour is not covered by automated tests.
- Standard and Mini were inspected visually; switching back and forth during playback was exercised. The Mini choice then really is in the local library. An additional test covers size persistence and the migration of existing libraries while keeping queue and volume.
- Mini was enlarged to 192 × 108 points of video on request; whole-number dimensions replaced the original third-of-width. The updated view was inspected again.
- A YouTube link was pasted through the native clipboard: the input field then holds the complete link and the plus button becomes active.
- `⌘A` and deleting in the input field were exercised.
- The pop-out was inspected visually on 11 September 2026: a borderless video in a floating window. The new medium size, 320 × 180 points, was confirmed in the running app, and `medium` then really is in the local library. Full-screen spaces and switching between several displays were not exercised.
- The build produces an ad-hoc signed bundle locally; `codesign --verify --strict` passes.

Clipboard detection and confirmation were added after the playback test and were covered by the full run. A long-running test over several hours, every kind of YouTube video, and older macOS versions are not covered.
