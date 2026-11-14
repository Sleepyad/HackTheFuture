# Team Plan (4 people, deadline ~15:30, merge at 14:30)

Most PDF stories are already done in the working game. This covers what's left.

## What's already done

| PDF story | Status |
|---|---|
| A3 slow-mo, A4 speed ramp | Done (`Game` + `main.gd`) |
| A1 skater | Done, but it **auto-jumps**; PDF says Space |
| A2 obstacles | Boxes only, no ramps/gaps, **no collision penalty** |
| B1-B4 words, longer words, scramble | Done, popup not Windows 98 style yet |
| C1-C5 timer, bonus/penalty, difficulty, game over, title | Done. Missing: `-3s` display, obstacle penalty, score = time + words |
| D3 flicker and scramble | Done as code, no shader |
| D4 fake ads | Done, but auto-close and no clickable X |
| D1 sprites, D2 retro look, D5 audio | Not done |

**Skip `Events.gd`.** `Game` (`game.gd`) is already the signal bus:
- `player_jumped` = `Game.trick_started`
- `word_completed` = `Game.trick_succeeded`
- `letter_wrong` = `Game.key_wrong`
- `time_up` = `Game.game_over`
- `level_changed` = `Game.difficulty` (continuous, 0 to 1)
- Missing: `player_landed`, `player_hit_obstacle` (P3 adds them)

## Who does what (separate files, no clashes)

**P1: World and gameplay** - owns `main.gd`, `main.tscn`
- Obstacle variety: ramps and gap visuals, 2-3 chunk patterns
- Obstacle hit = time penalty (P3 adds `Game.penalty(seconds)`)
- Wire in P4's background art
- Integrator at 14:30

**P2: Popup and HUD** - owns `hud.gd`, `hud.tscn`
- Windows 98 style word popup (title bar, X button, pixel font)
- `+2s` / `-3s` floating text, air-time bar
- Fake ads with clickable X; must never block typing (keep `mouse_filter = IGNORE` except the X)
- Flicker shader

**P3: Rules, score, export** - owns `game.gd`, `screens.*`, `project.godot`
- Add `Game.penalty()`, `player_landed`, words-completed counter
- Score = survived seconds + words, shown on game over
- Tune `Game` constants (`START_TIME`, `RAMP_SECONDS`, bonus/penalty)
- **Web export + itch.io upload at 14:00**, again at the end

**P4: Art and audio** - owns `skater.*`, plus new files only
- Skater sprites in `skater.tscn`, replacing the `play_*` stubs in `skater.gd`
- Background/parallax PNGs and pixel font in `art/` (P1 wires them in)
- New `audio.gd`: 1 song + 3 sounds (jump, success, wrong) driven by `Game` signals; P3 adds the autoload line

## Timeline

| Time | What |
|---|---|
| 13:35 | 10 min sync: clone, open project, F5, create own branch |
| 13:45-14:30 | Build your own stories, commit and push small and often |
| 14:00 | P3: first web export, check keyboard focus in browser |
| 14:30 | Everyone pushes, P1 merges into `main` |
| 14:30-15:15 | Play full runs together, fix bugs, retune difficulty |
| 15:15 | Final export + itch.io upload, feature freeze |
| 15:30 | Deadline |

**If late, cut in this order:** audio, fake ads, sprites (placeholders work).

## Git rules

- One branch per person; nobody edits another person's files
- Only P3 edits `project.godot`
- Always commit `.uid` files
- Repo owner adds the other three as collaborators

**To decide at sync:** Space to jump (PDF) or auto-jump (current)? This changes P1's work.
