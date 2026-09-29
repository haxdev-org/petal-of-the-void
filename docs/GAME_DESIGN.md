# Petal of the Void — Game Design (draft)

A turn-based RPG for phones (landscape), adapted from the novel in `story/`.
Visual style: **HD-2D**, meaning pixel-art characters in lit 3D dioramas with
bloom, tilt-shift depth of field, fog and drifting petals.

## Core fantasy

You play Baihua, an android from another dimension who crash-lands in a
cultivation world with no memory. She is overwhelmingly capable but hides what
she is. The game should feel like the prose: precise, quiet, atmospheric, with
bursts of devastating power.

The novel's voice carries into the UI. Baihua's italic diagnostic lines
(*"Threat assessment: minimal."*) are the battle log, the field hints and the
system messages.

## Battle system

Turn order uses **charge time (CT)**. Each combatant fills CT at its speed and
acts at 100, so faster units act more often. The next five turns are shown
on screen.

Baihua's mechanics come straight from the story bible:

| Mechanic | Source in novel | In game |
|---|---|---|
| **Chassis strikes** | Fusion-core-powered physical superiority | *Precise Strike*: free, builds heat |
| **Qi techniques** | Ch14 chassis meridians, Ch17 Flame Path copies | *Compression Palm*, *Thousand-Year Ember*: cost qi |
| **Combat qi regeneration** | Ch17: core refills dantian at expenditure rate | +8 qi at the start of every turn |
| **Stellar Core heat** | Ch3/Ch10 regulator override, amber-gold glow, steam | Heat gauge (0–100) fills from actions and hits; at 100, *Stellar Discharge* hits all enemies |
| **Technique copying** | Ch17: maps any technique on one observation, auto-optimises | When an enemy uses a copyable technique, Baihua learns a stronger, cheaper version for the rest of the battle |
| **Nanobot repair** | Ch4/10/18 nanobot configurations | Heal 30% integrity for qi |
| **Stillness** | Her uncanny stillness; the fake "Stilled Surface Form" | Guard: halve damage, restore qi |

### Ideas for later

- **Qi-signature masking** (Ch18): a "concealment" meter. Holding back in
  front of witnesses (villagers, sect elders) earns story rewards; unmasked
  violet output spooks NPCs.
- **Orbital platforms and drones** (Ch13–14): a late-game summon with a long
  cooldown. *"Observe."*
- **Copied techniques that persist**: pick which mapped techniques to keep,
  with limited "cognitive core slots".
- **Party members** for the sect arc: Chen Mao (wood), Bei Jingru (water),
  Cui Hao (earth), Fen Liuying. Baihua can optimise their forms (Ch9), which
  works as a skill-upgrade system.
- **Elemental alignment** and resistances as the sect arc begins.

## Structure (proposed)

| Act | Chapters | Setting | Boss |
|---|---|---|---|
| Prologue | 1–3 | Broken Tooth Ridge → Silverwind City → serpent cave | Jade Canopy Serpent |
| I | 4–6 | Vermillion Capital, the Grand Disciple Recruitment (tournament arc) | Luo Fengying (duel) |
| II | 7–11 | Eternal Flame Order, library, northern passes | Earth Dragon |
| III | 12–15 | Auction, Iron Cauldron plot, orbital launch | Iron Cauldron ambush / the three elders |
| IV | 16–18 | Spirit Condensation, departure, the road north | Wolf-Demon, into the Tangled Canopy |

**First vertical slice:** the Prologue (Chapters 1–3). It opens with the
crater, the bandits, the acid-fang wolves and the Serpent's cave, and ends on
the first Stellar Core release. The current skeleton covers the crater area
with placeholder encounters.

## Current skeleton

- Title screen (key art) → Chapter One illustrated intro → Broken Tooth Ridge field → battles.
- Three encounters on the ridge: acid-fang pack, quill-bear, wolf-demon.
- Save/continue, graphics quality toggle, touch controls (tap to move, or a
  floating joystick in the lower-left).
