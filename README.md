# SpeakTyper

Press a shortcut, talk, and your words get typed into whatever app you're in.
Transcription runs fully on-device with NVIDIA **Parakeet TDT 0.6B v2** on the Apple Neural Engine (via [FluidAudio](https://github.com/FluidInference/FluidAudio)).

## Use
| | |
|---|---|
| **Hold Right ⌥** | push-to-talk — release to stop & type |
| **Tap Right ⌥** | hands-free — tap again to stop & type |
| **Esc** | cancel while listening |

The trigger is the right-hand Option key on its own, which almost nothing else uses. Pressing it as part of a
shortcut (e.g. ⌥E for an accent) is ignored.

A black, HUD-style dynamic island grows out of the notch only while you dictate:
`LISTENING` + a live `00:04.2` timer beside the notch; below it, a voice orb (glowing core, radial ticks
that stretch with your voice, rotating dial arcs) next to a spectrum of translucent grey bars over a
dot-matrix grid, with a light that orbits the island's rim. Twin beams sweep while Parakeet transcribes,
then `INSERTED · N WORDS` and it folds back into the notch.
The menu bar icon (waveform) has toggles for a trailing space and sounds.

## Build
Requires an Apple Silicon Mac, macOS 14+, and Xcode (Swift 6).
```
git clone https://github.com/AKAbhinav99/speaktyper.git
cd speaktyper
./build.sh
```
This produces `SpeakTyper.app` (ad-hoc signed with a stable identifier requirement, so Mic/Accessibility
permissions should survive rebuilds).

To install it and have it start automatically when you log in:
```
./build.sh --install
```
That copies the app to `/Applications` and launches it; on launch it registers itself as a login item
(System Settings → General → Login Items). Turn it off any time with **Launch at Login** in the menu bar icon.

## First run
1. Launch it (`./build.sh --install` does this) — a waveform icon appears in the menu bar
2. Allow **Accessibility** (System Settings → Privacy & Security → Accessibility) so it can type.
   Without it, text is copied to the clipboard instead.
3. Allow **Microphone** the first time you dictate.
4. The model (~450 MB) downloads once to `~/Library/Application Support/FluidAudio/Models`.

## Tweak
`Sources/SpeakTyper/Config.swift` — shortcut, push-to-talk threshold, model (`.v2` English, `.v3`/`.ultra` multilingual).

Debug helpers: `SpeakTyper.app/Contents/MacOS/SpeakTyper --transcribe file.wav [--channels 3]` and `--demo`.
Each dictation logs a line (`SpeakTyper: 2.4s audio, peak 0.71 → 38 chars`) to Console.app.
