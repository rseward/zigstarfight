# ZigStarfight

A 2-player vector space combat game built on the [zigvectorgames](https://github.com/rseward/zigvectorgames) platform, inspired by the classic Spacewar! and the [pystarfight](https://github.com/rseward/pystarfight) Python game.

Two ships duel around a central star with gravity, missiles, and toroidal screen wrapping. First to score the target number of kills wins.

## Controls

### Player 1 (Triangle Ship — White)
- A / D: Rotate left/right
- W: Thrust
- TAB: Fire missile
- S: Hyperspace

### Player 2 (Hex Ship — Pink)
- Left / Right arrows: Rotate
- Up arrow: Thrust
- Right Shift: Fire missile
- Down arrow: Hyperspace

### General
- P: Pause
- R: Restart match
- F: Toggle fullscreen (platform-level)
- ESC: Quit

## Features
- Central gravity star that pulls ships and bullets
- Toroidal screen wrapping (fly off one edge, appear on the other)
- Vector-drawn ships with thrust flames
- Missile combat with limited active bullets per ship (4 max)
- Ship explosions with debris particles
- Automatic respawn after destruction
- Score tracking — first to 5 kills wins
- MSAA anti-aliasing and bloom/glow post-processing (via vgame platform)
- Sound effects (shoot, thrust, explosion, tonal bleeps)

## Build

Requires Zig 0.15.2 ([zvm](https://github.com/ziglang/zvm)).

```
zig build run
```