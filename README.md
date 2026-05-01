# BeatDropper

BeatDropper is a desktop DJ set player for local music files and AI-assisted transitions.

It gives DJs a focused workspace to load prepared tracks, shape the running order, monitor the current mix, and keep the next transition ready.

## DJ Set Workflow

BeatDropper is organized around the flow of running a set:

1. Load prepared MP3/WAV tracks as a new set.
2. Add more tracks to the current playlist when the set changes.
3. Arrange the running order directly in the playlist.
4. Review the current track, AI mix plan, and next track in the queue cockpit.
5. Start playback and let BeatDropper prepare the next transition.

The playlist remains the center of the workspace. The queue cockpit stays focused on the information needed during playback: what is playing now, how the transition is planned, and what comes next.

## Queue Cockpit

The main performance view is built around three states:

- `Now Playing`: the active track, playback state, BPM, length, and outro cue.
- `AI Mix Plan`: transition window, next-track offset, style, and confidence.
- `Next Track`: the upcoming track, BPM, length, and intro cue.

This layout keeps the DJ workflow visible without turning the screen into a settings panel or debugging console.

## AI-Assisted Transitions

BeatDropper can request a transition plan from an external AI planner. The planner can suggest:

- where the current track should begin fading
- where the transition should end
- where the next track should start
- which transition style fits the track pair
- whether tempo sync should be applied

The player validates AI plans before applying them and keeps a built-in transition path available for stable playback.

## Playlist Control

The playlist is designed for set operation:

- load a new set
- add tracks to the current set
- select the starting track
- reorder tracks
- remove tracks from the set
- clear the playlist

Track rows surface practical DJ information such as title, BPM, length, format, cue points, and mix readiness.

## Desktop App

BeatDropper runs as an Electron desktop app and uses local files as the source for playback. The interface is styled as a dark DJ workspace with icon-based controls, a compact transport area, and a playlist-first layout.

## Run Locally

```bash
npm install
npm run dev
```

For WSLg or GPU-sensitive environments:

```bash
BEATDROPPER_DISABLE_GPU=1 BEATDROPPER_OPEN_DEVTOOLS=0 ELECTRON_DISABLE_GPU=1 npm run dev
```

## Validation

```bash
npm run test
npm run build
npm run test:e2e
npm run test:e2e:electron
```
