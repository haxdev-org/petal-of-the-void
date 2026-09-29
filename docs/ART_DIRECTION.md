# Art Direction

There are two layers of art. They share one palette and one mood.

1. **Illustrations**: story panels, portraits, key art. This is the ink-and-
   watercolour manga style of the uploaded Chapter One panels (`art/`). Used
   for cutscenes, the title screen, dialogue portraits and loading screens.
2. **In-world HD-2D**: pixel-art sprites in 3D dioramas. Used for exploration
   and battles.

## Palette

| Role | Colour | Notes |
|---|---|---|
| Baihua's hair | `#E8C872` | Burnished pale gold, faintly luminous, never yellow |
| Robe | `#233268` / shadow `#151D42` | Deep ink-blue silk |
| Embroidery, gloves, sash | `#F2F0EA` | White blossoms at hem and cuffs |
| Chassis | `#E9E6E0` with dark crack lines | White ceramic composite, cracked |
| Qi / core glow | `#FFD173` gold, `#A880FF` violet | Gold threaded with violet; violet grows through the story |
| Stellar Core mode | `#FFB35C` | Amber-gold "star through atmosphere" |
| Dusk sky | `#141433` → `#C98A6A` | Default outdoor mood |
| Eternal Flame Order | `#B8452A` | Banked-coal orange-red |
| Demon eyes | `#FF3A2A` | Red luminescence of corrupted qi |

## Illustration prompts (Gemini)

Keep the style prefix identical on every prompt so panels match:

> **Style prefix:** *Ink-and-watercolour manga illustration, bold black ink
> linework, muted watercolour washes, dusk palette of indigo, violet and ember
> orange, atmospheric mist, cinematic 16:9 composition, wuxia fantasy world.*

> **Baihua description:** *petite young woman android, long loose pale-gold
> hair to mid-back, large dark eyes, calm uncanny stillness; wearing a deep
> ink-blue silk robe with white blossom embroidery at hem and cuffs, pale grey
> inner collar, white silk sash, long white silk gloves, low blue leather
> boots.* (Pre-robe scenes: *white ceramic-composite armour with fine cracks*.)

Attach an approved panel as a reference image each time and say "same
character, same outfit, same style". This keeps her on-model.

**Dialogue portraits:** ask for *"bust portrait, neutral background of soft
indigo wash, looking slightly off-camera"* in five expressions: neutral,
assessing, faint surprise, troubled, and gentle (rare).

## Sprite spec (in-world)

- Characters about **48–64 px tall**, drawn at 1x, rendered with nearest-
  neighbour filtering. Limited palette (16–24 colours per character).
- Animations: idle (4 frames), walk (6–8 frames per direction, 4 directions or
  mirrored 2), attack, cast, hurt, down. Battle poses face right (party) and
  left (enemies).
- Export as horizontal strips per animation, e.g.
  `art/characters/baihua/walk_down.png`.
- AI image tools help with concept and turnarounds, but walk and attack cycles
  need hand clean-up in Aseprite. Budget time or a pixel artist for this.

**Sprite prompt (for concept only):**

> *Pixel art character sprite sheet, 64x64 pixel grid, limited 24-colour
> palette, front / side / back views, no anti-aliasing, transparent background,
> JRPG HD-2D style, [character description]*

## Environments

Build dioramas from modular low-poly pieces with painted textures: rocks,
pines, bamboo, stone paths, sect architecture. Keep scenes small and enclosed
(ridges, forest walls, courtyards) so the camera never shows an empty horizon.
Fog and particles sell the depth. Environment concept paintings in the
illustration style are the best brief for each area.

## Watermarks

Gemini adds a sparkle watermark in the bottom-right corner. The game crops it
when displaying panels (see `region` in `game/scenes/story/intro.gd`). For store
or marketing images, crop it in the source file.
