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

## In-world sprites: rendered from 3D, eight facings

The in-world characters follow the Infinity Engine recipe (Baldur's Gate):
each character is a simple 3D model that is rendered from the game's exact
camera (orthographic, 42 degrees down) at 8 facings and turned into pixel
art. That is what gives Baldur's Gate sprites their look, and it keeps
Baihua's armour, hair and robe consistent from every angle without drawing
dozens of frames by hand.

Pipeline (all in `game/tools/`):

1. `blender_sprites.py` builds the characters inside Blender (Baihua in
   the cracked chassis and in the robe, the acid-fang wolf, the quill-bear),
   poses each animation frame, and renders every frame at 8 facings, twice:
   lit (Cycles, one sun from the camera's upper left plus soft ambient) and
   as flat material IDs. Humanoids are assembled from rounded blobs
   (subdivision-smoothed boxes) and tapered tubes hung off joint empties;
   the animals' bodies are metaball families (`mball()`), so chest, neck,
   haunches and legs fuse into one organic surface, with dark muzzles, ears
   and paws as meshes on top.
2. `post_sprites.py` downsamples the 2x renders, looks up each pixel's
   material, quantises its brightness onto that material's 5-tone
   hue-shifted ramp, adds the selective outline and writes the sheets plus
   a JSON sidecar. The wolf-demon is the wolf with a palette swap.
3. The game (`core/sprite_sheets.gd`) loads `assets/sprites/<id>.png`
   + `.json`; animations are named `<anim>_<dir>` with dir 0 = screen
   right, counter-clockwise (2 = away from the camera, 6 = toward it).

Scale: 44 px per metre. Baihua is 1.64 m; the wolf-demon is rendered from
the wolf model and displayed 3x larger.

Re-render everything with:

```sh
blender --background --python tools/blender_sprites.py -- /tmp/renders
python3 tools/post_sprites.py /tmp/renders
```

To improve a character, edit its model or poses in `blender_sprites.py`;
to change its colours, edit `MATERIALS` in both scripts. Pass `smoke` on
the command line to render only two facings of the first frames for a
quick look. When a real modelled character arrives (a `.glb` from an
image-to-3D tool or an artist), the same render and quantise steps apply:
import it in place of the procedural builder and keep the material names.

## Environment art

Ground, rock and bark are 128 px tileable pixel textures with normal maps
(`gen_textures.py`), one tile per 1.45 m; a large soft "macro" variation is
multiplied over the ground so the repeat never shows. Props are low-poly
Blender models (`blender_props.py`: pines, boulders, cliffs, the impact
crater, fallen logs, stumps) textured in-game by mesh name. Decals
(scorched clearing, path, pebbles) are soft-edged quads laid on the ground.

The crater is real terrain: `HD2D.crater_height()` mirrors the profile
used to build the mesh so Baihua walks down into the bowl.

## Camera

Fixed isometric view like Baldur's Gate: yaw 45 degrees, pitch 42 degrees,
orthographic (`HD2D.build_iso_camera`). The horizon is never on screen, so
maps need a dense treeline or cliffs at their edges rather than a skybox.
Fog, light shafts, petals and a vignette add depth.

## Watermarks

Gemini adds a sparkle watermark in the bottom-right corner. The game crops it
when displaying panels (see `region` in `game/scenes/story/intro.gd`). For store
or marketing images, crop it in the source file.
