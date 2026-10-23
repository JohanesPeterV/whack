# Whack! requirements handover

Working name: **Whack!** Final branding is open. Mac Drums suggests a music app; this should feel like a cheeky toy that makes your Mac react to a tap.

## Goal

Build a simple macOS app that plays a sound when a compatible MacBook is tapped. Keep the playful appeal of moan sounds and funny reactions, while making setup and sound management easy for ordinary users.

The whole setup should be: **open app → choose a sound → switch on → tap**.

## What we aim to beat

[Spank](https://github.com/taigrr/spank) is the primary benchmark. It already detects impacts, plays custom MP3s, and supports sensitivity and escalating reactions. Its documented custom-sound workflow uses terminal commands and a folder of MP3 files.

Our target is a smoother experience: a normal Mac app with every everyday control and sound-management action inside it. Users should be able to enjoy the joke immediately and add their own sounds without managing folders or commands.

[MacSlap](https://macslap.com/) already offers a menu-bar interface, and [BonkMac](https://bonkmac.com/vs-slapmac/) advertises custom sound packs. A GUI alone is not a new feature; our advantage must come from how easy the complete flow feels. Bonk is also already used in this category, so avoid that name.

## First version

- One compact menu-bar window with a clear on/off switch.
- A small bundled sound library, including a clearly labelled moan preset and other funny reactions, ready to preview and use.
- A sound list with preview and selection controls. Selecting a sound makes it the reaction for each tap.
- Add sounds through a file picker or drag and drop. Start with MP3 and WAV.
- Rename, replace, and delete imported sounds directly in the app.
- Store an app-managed copy of every imported sound. Keep original files untouched; moving or deleting them must not break playback.
- Remember the selected sound and sensitivity between launches.
- Keep sensitivity and a short playback cooldown in settings, with useful defaults.
- Handle invalid audio and unavailable sensors with a clear message and an obvious next step.

Keep the interface small and playful. Prioritise this flow before adding personalities, audio editing, sharing, or extra triggers.

## Ready when

- A fresh install can preview a bundled sound and react to a gentle tap through the app's setup flow.
- Import, preview, select, rename, replace, and delete all work without opening Finder to organise a library.
- An imported sound still plays after its original file is moved or deleted, including after restarting the app.
- Deleting the selected custom sound falls back to a bundled sound and leaves the app usable.
- Switching off stops tap reactions; normal typing does not repeatedly trigger them.

## Start here

First prove motion-sensor access and audio playback on the actual target MacBook. Sensor compatibility and permissions need verification; do not assume every Apple Silicon model works or that elevated access can always be avoided. Explain any required permission through the app.

Use original or appropriately licensed bundled audio. The first implementation milestone is the complete setup and sound-management flow above. App implementation has not started.
