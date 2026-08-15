# Mino PoC

An intentionally small native macOS proof of concept for Mino's desktop-pet runtime.

## What it validates

- Two independent transparent AppKit panels.
- One `PetWorld` as the source of runtime position and activity state.
- SpriteKit avatars composed from species, body color, eyes, hats, and accessories.
- A world-level kiss interaction that coordinates both pets and a separate heart effect window.
- An adaptive 30 FPS motion timer that stops when no pet or interaction is moving.

The artwork is generated from SpriteKit shapes and has no external asset dependency.

## Build and run

```sh
Scripts/build-app.sh
open .build/MinoPoC.app
```

Use the `♡` menu bar item for debug actions. Clicking either pet also triggers the kiss interaction in this PoC.

## Scope

This is not the production Mino architecture. It intentionally excludes accounts, networking, persistence, databases, AI, a store, and formal asset tooling.

