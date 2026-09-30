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

Baihua's kit follows the novel's timeline. She has **no concept of qi until
she cultivates** (Chapter Fourteen), so the early game is fought with what
she crash-landed with: the chassis, the fusion core, the nanobot colony and
her sensors. Story flags unlock the rest (`Db.player_data()`).

**From the crash (Chapter One):**

| Command | Source in novel | In game |
|---|---|---|
| **Precise Strike** | Chassis speed and precision | Free; builds core heat |
| **Core Surge** | She draws surges from the fusion core into her limbs | Heavy strike; spends 40 heat |
| **Sensor Sweep** | Her constant analysis of every opponent | Maps a target: her hits on it land 35% harder for 3 turns |
| **Nanobot Repair** | The maintenance colony (Ch 4/10/18 configurations) | Restores 30% integrity; costs 25% colony mass, which regrows 4%/turn |
| **Stillness** | Her uncanny stillness | Halves incoming damage |
| **Stellar Discharge** | Ch 3 / Ch 10 regulator override | At 100 heat, raw fusion output hits every enemy |

Resources on screen: **Integrity** (HP), **Core heat** (fills from her
actions and from being hit), **Nanobots** (colony mass).

**After the artificial path (`cultivation`, Chapter Fourteen):** a **Qi**
bar appears, refilled every turn by the core (Ch 17 combat regeneration),
and *Qi Palm* joins the Techniques menu.

**After the plateau spar (`technique_mapping`, Chapter Seventeen):** she
copies any copyable enemy technique on first observation, optimised
(+10% output, -15% cost), and carries the Flame Path techniques she learned
from Elder Shen (*Compression Palm*, *Thousand-Year Ember*).

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
