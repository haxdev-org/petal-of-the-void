# Petal of the Void

A turn-based HD-2D RPG for mobile, adapted from the novel *Petal of the Void*.

| Folder | What's in it |
|---|---|
| `story/` | The novel chapters and the story bible |
| `art/` | Source art (story panels, key art). See `art/README.md` |
| `game/` | The Godot 4.7 project |
| `docs/` | Game design and art direction |

## Running the game

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, not .NET).
2. Open `game/project.godot` in Godot and press **F5**.

The mouse stands in for touch: click to move, or click and drag in the
lower-left of the screen for the joystick. WASD and the arrow keys also work.

## Running the tests

The battle rules are plain GDScript with no scene dependencies, so they run headlessly:

```sh
cd game
godot --headless --import              # first time: builds the class cache
godot --headless -s tests/run_tests.gd
```

## Screenshots

`tools/capture.tscn` visits each scene and saves screenshots:

```sh
godot --path game res://tools/capture.tscn -- /path/to/output
```

## Putting it on a phone

**Android:** the project includes an Android export preset (`game/export_presets.cfg`:
arm64, release, no Gradle build). One-time setup: in Godot use *Editor → Manage
Export Templates → Download*, install the Android SDK (platform-tools and
build-tools), and set the SDK and Java paths under *Editor Settings → Export →
Android*. Then build:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=<alias>
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password>
cd game && godot --headless --export-release "Android" ../build/petal-of-the-void.apk
```

Never commit the keystore or its password. Android only accepts an update
signed with the same key as the installed app; a build signed with a different
key needs the old app uninstalled first.

**iOS:** export from Godot on a Mac, then build and sign in Xcode.

## Code layout (`game/`)

- `autoload/`: global singletons: `Settings` (quality, input), `GameState` (flags, save/load), `SceneRouter` (fade transitions)
- `battle/`: `BattleSystem` and `Combatant`: turn order, damage, technique copying. No scene code.
- `data/`: `SkillData`, `CombatantData` and `Db` (all skills, monsters and encounters)
- `core/`: `HD2D` (lighting, bloom, depth of field, fog, petals, props) and `PixelArt` (placeholder sprites)
- `scenes/`: title, Chapter One intro, the field (Broken Tooth Ridge) and battle
- `ui/`: theme, virtual joystick, full-screen illustration viewer
- `assets/`: art copied from `art/` for use in the game

Placeholder sprites are drawn from text grids in `core/pixel_art.gd`. When real
sprite sheets arrive, only `PixelArt.texture()` needs to change.
