# Mino Demo

A presentation-ready native macOS demo for Mino's desktop-pet experience.

## What it validates

- Two independent transparent AppKit panels.
- One `PetWorld` as the source of runtime position and activity state.
- SpriteKit avatars composed from species, body color, eyes, hats, and accessories.
- Named partner identities, grounded shadows, movement feedback, and semantic emotions.
- World-level kiss and flower-gift interactions with independent effect windows.
- A deterministic, replayable demo sequence from the menu bar.
- An adaptive 30 FPS motion timer that stops when no pet or interaction is moving.

The artwork is generated from SpriteKit shapes and has no external asset dependency.

## Build and run

```sh
Scripts/build-app.sh
open .build/MinoPoC.app
```

Use the `♡` menu bar item and choose **播放完整 Demo** for the full sequence. The same menu can replay either interaction, change the partner's outfit, walk, or reset the scene. Clicking either pet triggers the kiss interaction.

## Scope

This is still not the production Mino architecture. It intentionally excludes accounts, networking, persistence, databases, AI, a store, and formal asset tooling.
