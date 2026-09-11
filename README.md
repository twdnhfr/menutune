<p align="center">
  <img src="Support/Brand/menutune-logo-256.png" alt="MenuTune logo" width="128" height="128">
</p>

# MenuTune

A private YouTube mini player for the macOS menu bar. Open the player with a click, start your music, and fold the menu away again. The same web view stays alive throughout.

## Getting started

Requirements: macOS 14 or newer and an installed Swift 6 toolchain (Xcode). No extra packages, no API key, no server of your own.

```sh
bash scripts/build-app.sh
open build/MenuTune.app
```

MenuTune sits in the menu bar as a waveform. A small dot at its lower right shows the state: green while playing, yellow when paused, no dot when idle. The app has no Dock entry. Right-click reaches play/pause, the next track and quit.

## Using it

- **⌘⇧Y** opens and closes the player globally, even while you work in another app. Closing it with the shortcut hands the focus back to the previous app. Playback continues either way.
- The size switch at the bottom cycles **Standard** (448 × 252 points of video), **Medium** (320 × 180) and **Mini** (192 × 108). Mini shows only the video and the bottom bar. Playback continues across a size change; the chosen size is stored locally and applies to the pop-out window too.
- The pop-out button at the bottom left detaches the video into a borderless window that floats above everything. It dodges the pointer between **bottom right → middle right → top right → middle right → bottom right** and skips positions that are already taken. The Dock and the menu bar are respected, and clicks pass through the window to whatever you are working in.
- Use the menu bar icon or **⌘⇧Y** to control it or bring it back. The size of the detached video can be changed there as well. Play/pause and the next track stay reachable from the right-click menu. After an app restart the pop-out mode starts off.
- Paste a YouTube link and add it to the queue with **+**. Enter adds the track and starts it right away.
- Every video appears in the queue at most once. A link that is already queued does not create a second entry; the status line says so, and Enter starts the entry that is already there. Older lists holding duplicates are merged once on load, keeping the first entry with its title and position.
- Opening the player checks the clipboard once for a YouTube link. The checkmark takes it into the queue, the cross discards the suggestion until you copy something new. Nothing is added or started without confirmation. There is no background clipboard monitoring.
- The usual Mac shortcuts, `⌘V`, `⌘C`, `⌘X`, `⌘A` and `⌘Z`, work in the link field.
- Links from `youtube.com`, `youtu.be`, YouTube Music, Shorts, Live and Embed are supported; a time parameter such as `t=3s` is honoured when a link is started directly.
- Click a track to play it. Its action menu moves or removes it.
- Play/pause, volume and position are operated inside the YouTube player itself. There is no second set of controls. The status dot follows those player actions too.
- The menu next to **Queue** repeats a single track or the whole list. The next track and play/pause are also reachable by right-clicking the menu bar icon.
- Clicking **Queue** folds the list open and shut, which keeps the player compact. The state is stored locally and carries over to the next start.
- Should YouTube block a video for embedded players, MenuTune skips it while playback is running and shows the reason in the status line. If every track is blocked, playback stops with a message.
- If you start a YouTube recommendation inside the video, the status display follows it. Play/pause then act on that video; the queued track resumes only after you click its row.
- Clicking outside, or the arrow at the top, closes the menu. It does not open by itself when the track changes.
- Errors appear inside the player. They never open an extra window.
- Queue, volume, player size and the folded state of the list are stored locally. No playback starts automatically on the next launch.

The local file lives at `~/Library/Application Support/MenuTune/library.json`. If it is damaged it stays untouched, and a message points out that changes are not being saved for now. Restart the app once you have restored or replaced the file.

## Current scope

Version 0.1 is a feasibility prototype with a saved queue. Multiple named playlists, automatic recommendations, hover previews, Google sign-in, media keys and launch-at-login are not included yet. Not every YouTube video allows playback in embedded players. Those tracks are skipped; the embedded player shows its own link for opening them on YouTube.

Playback uses the ordinary YouTube IFrame player inside a persistent `WKWebView`. Nothing is downloaded, no audio track is extracted, and no ad blocking is built in. Metadata comes from YouTube's oEmbed endpoint. YouTube receives the usual web requests while loading and playing, and may store cookies in the app's own web view; the app imports no browser cookies.

YouTube's developer policies forbid background players. Private use is not a guaranteed exception. Hiding and showing the window here is explicitly a personal technical prototype; nothing assumes it keeps working across future changes by YouTube or WebKit.

## Development and tests

```sh
swift test
bash scripts/build-app.sh
```

An optional test against the real player logs playback with the menu visible and closed, pause and resume, an automatic track change, replay inside the embed, and recovery from simulated loading and process failures. It uses the library you pass in and deliberately puts a second copy of the same video there for the track change, which the interface itself refuses. Without `--library` it does not start, so your real list stays untouched. It runs only with these arguments:

```sh
build/MenuTune.app/Contents/MacOS/MenuTune \
  --library "$PWD/build/smoke-library.json" \
  --play-url 'https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s' \
  --smoke-test 2>build/playback-smoke.log
```

The test evaluates YouTube's state messages and the player time; WebKit's media state is logged alongside but does not feed the verdict. It is no proof that speakers or headphones actually emit sound. During the test the menu opens and closes deliberately. That does not happen in normal use.

The test only begins once the player is visibly open; click the menu bar icon if needed. The sequences it covers and their limits are documented in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Publishing

`scripts/release.sh` produces a notarised, stapled universal DMG. The script never reads credentials itself; they live in the keychain under a notarytool profile that you create once:

```sh
xcrun notarytool store-credentials <name> --apple-id <your Apple ID> --team-id <your team>
```

Put the profile name into `scripts/release.env`, for which `scripts/release.env.example` is the template. That file stays out of the repository, and an environment variable of the same name wins over it. `SIGN_IDENTITY` optionally forces a particular signing identity; otherwise the first matching one in the keychain is used.

After that a single call is enough. The script checks the certificate, a clean working tree and the notarisation profile first, stops immediately on a problem, and only then builds:

```sh
bash scripts/release.sh
```

It runs in this order: tests, universal build for Apple Silicon and Intel, signature with the Developer ID plus hardened runtime and secure timestamp, notarisation of the app followed by stapling, packaging into the disk image, signature and notarisation of the image, stapling, and a closing `spctl` verdict. The app gets its own ticket so an installation dragged out of the image stays verifiable without a network connection. The result lands under `build/release/`.

`--skip-notarize` produces everything except the Apple round trip. Gatekeeper rejects that result and it does not belong on a website; the script says so and names the directory accordingly. `--allow-dirty` builds from an uncommitted tree. The build number in the app is the commit count, the version number lives in `Support/Info.plist`.

## Layout

- `MenuTuneCore`: link validation, the queue and atomic local storage.
- `MenuTune`: the AppKit menu bar, the SwiftUI interface and the WebKit player.
- `Resources/player.html`: a small bridge to the YouTube IFrame API.
- `scripts/build-app.sh`: builds the app bundle. Without arguments locally and ad-hoc signed for the current architecture, with `--universal --sign` for the release path.
- `scripts/release.sh`: the full way to a publishable DMG.

References: [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference), [native embed identification](https://developers.google.com/youtube/terms/required-minimum-functionality#Set_the_Referer), [YouTube developer policies](https://developers.google.com/youtube/terms/developer-policies).
