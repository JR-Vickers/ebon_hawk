# KOTOR2 ship asset pipeline

This pipeline reads a local KOTOR II installation. It does not include or distribute game assets. The default project scene remains the placeholder; the ship is a separate, experimental navigation preview.

## Inputs and pinned tools

- KOTOR II `GameData`, including `chitin.key`, `data`, `Modules`, `TexturePacks`, and `override`. On the development Mac this is inside `Knights of the Old Republic II/KOTOR2.app/Contents/GameData` in Steam's common directory.
- Python 3.12 and PyKotor 2.3.12, installed to `build/kotor-python`.
- Blender 5.3.0 for Apple Silicon (tested build `02f0899d78e3`) and KotORBlender revision `afae04c9172f30ab765891315d9d11224ab57426`. KotORBlender is GPL-3.0; it remains an external tool and is not included in this project.

Install PyKotor with `uv pip install --target build/kotor-python pykotor==2.3.12`. Obtain Blender 5.3.0 for Apple Silicon and unpack or mount it. Download the specified KotORBlender revision from its GitHub repository and unpack it into `build/kotorblender-afae04c9172f30ab765891315d9d11224ab57426`.

## Generate and run

From the project root, set `GAME_DATA` to the local installation's `GameData` directory and `BLENDER` to the Blender executable. Then run:

```sh
PYTHONPATH=build/kotor-python python3.12 tools/extract_ship.py --game "$GAME_DATA"
"$BLENDER" --background --factory-startup --python-exit-code 1 \
  --python tools/import_ship_blender.py -- \
  --addon build/kotorblender-afae04c9172f30ab765891315d9d11224ab57426 \
  --input assets/extracted/ship --output assets/generated/ship/ebon_hawk.glb
"$BLENDER" --background --factory-startup --python-exit-code 1 \
  --python tools/export_ship_furniture.py -- \
  --assembly assets/generated/ship/ebon_hawk.blend \
  --output assets/generated/ship/furniture_collision.glb
python3 tools/dev.py ship-check
python3 tools/dev.py run-ship
```

Extraction resolves the `003ebo` layout from `chitin.key`, then extracts its room models, companion MDX and WOK files, and referenced textures and lightmaps. Texture selection checks the local override directory, then texture packs A, B and C, then the KEY/BIF data. Embedded texture metadata is written as TXI sidecars, with local TXI overrides taking precedence. Generated `manifest.json` records resource origins, layout hash, room names, and missing or failed textures. Binary source assets and output GLBs remain under ignored `assets/` directories. Re-running extraction uses the named resources from the current installation; local mods in `override` can affect texture output.

The Blender script retains the assembly in `ebon_hawk.blend` and exports visual geometry and the imported walkmeshes as separate GLBs. It writes `materials.json` and PNG dependencies alongside the visual GLB; the Godot wrapper uses those with the exported second UV set to multiply diffuse and original lightmap textures, including source self-illumination and alpha. The wrapper creates static collision from the walkmeshes and places the player at the central cabin. `R` returns to that spawn. The original placeholder is still launched with `python3 tools/dev.py run`.

## Live development reload

Start the updated preview once with `python3 tools/dev.py run-ship`. While it runs, changes to scripts, scenes, shaders, and generated ship assets are detected automatically and applied after two seconds without further writes. Press `T` in navigation mode or run `python3 tools/dev.py reload-ship` to request a reload manually. The request waits while the player has console input locked; `T` remains available to the target application during interaction. The preview preserves the player's position and view when reloading.

Reload first checks game scripts and runs `ship-check` in a separate headless process. A failed check leaves the current scene running; details are in `build/ship-reload-validation.log`. The check cannot establish visual correctness or catch every graphics-driver shader failure. If native code, engine configuration, or the reload host changes, restart the preview to apply those changes. Capture sessions may be recreated on a scene reload; the existing saved assignments are retained by their controller. The endpoint belongs to the most recently started preview in this checkout. `python3 tools/dev.py reload-check` exercises the reload and input-lock behavior headlessly.

## Current limitations

The extraction pass found 16 room models and 128 referenced texture/lightmap names with no missing source files on this Mac. The latest export mapped 899 objects; `Box18` and `Box19` lack required diffuse, lightmap, or UV inputs and remain on their imported material. The material manifest records these exceptions and each surface's alpha classification. Environment-mapped textures use alpha for reflectivity rather than transparency; the preview renders them opaque, but does not yet reproduce their reflections. Binary alpha uses cutout, intermediate alpha uses blending, and additive metadata selects additive blending. Classification is heuristic. Bump maps and vertex colors are also not reproduced by the shader. Blender produced 15 walkmesh objects; `003eboq.wok` has zero faces. A vertical ray at its layout origin found no collision, but this alone does not establish what that area needs. The user accepted the preview's rendering and collision for the MVP.

The separate furniture collision export selects 21 named source meshes: the central hologame table, five chairs and the curved panel behind three of them, the medbay table and bed, six crew bunks, two navigation chairs, and the cockpit chairs, instrument panels and central pilot controls. The selected source names are maintained in `tools/export_ship_furniture.py` and recorded in generated `furniture_collision.json`. These are triangle meshes, not an exhaustive inventory of all objects; some existing walkmesh collision may overlap them.

The user accepted the collision work as complete after these additions. After the transparency fix, the user also accepted the remaining subtle rendering differences from the game for the MVP.

The latest rebuild used Blender 5.3.0 from the mounted `/Volumes/Blender`. The documented pipeline has been exercised on this Mac; the user does not require verification on another computer. `ship-check` verifies generated material dependencies, spawn/reset, representative floor and wall collision, the central table, and player-capsule clearance through one central doorway; it is not a full navigation or rendering test.

## Observed source manifest

For this installation, the `003ebo` layout SHA-256 is `709a314e0b243f0d57a51e339a2ac93052e66b12513054737046107f1e98f987`. The layout comes from `data/Layouts.bif`; 16 model, 16 MDX, and 16 WOK resources come from `data/Models.bif`. The 34 diffuse textures come from `TexturePacks/swpc_tex_tpa.erf`; 94 lightmaps come from `data/Lightmaps.bif`. The generated local manifest records individual resource names and origins.

## Ship console overlays (M4, pending walkthrough)

The project-authored `ship_console.tscn` screens are independent of imported assets. The cockpit screen (`ship_cockpit`) is at `(50.28, 3.11175, -73.9805)` in front of the galaxy display on the left cockpit wall; the central screen (`ship_central`) is at `(42.64, 3.48, -49.26)` over the blue display on the central cabin back wall; and the medbay screen (`ship_medbay`) is at `(44.09, 3.15, -33.18)` on the curved wall opposite the medical bed. Their approach markers are respectively `(52.08, 1.8, -73.9805)`, `(44.12, 1.8, -48.24)`, and `(44.79, 1.8, -34.84)`. The headless ship check tests floor support, capsule clearance, unobstructed approach sight lines, and camera alignment. Visual mounting, routes and readability still need a Mac walkthrough.

Near a visible screen, P opens the window picker and E enters interaction after a source is live. Right Control (or the configured F12 key) releases input; click to resume navigation. Assignments use stable IDs and logical selectors; missing or ambiguous saved matches require reassignment. Reload waits for navigation mode, validates the candidate, stops old capture sessions, and then starts the replacement controller.

## Ship audio

Extract the music, ambient bed, and active positional emitters from the local game installation using the same `GAME_DATA` value as above:

```sh
PYTHONPATH=build/kotor-python python3 tools/extract_ship_audio.py --game "$GAME_DATA"
```

The generated files remain under ignored `assets/generated/ship_audio`. The extractor resolves the 003EBO area audio tables, its placed sound templates, and their clips, including the game's WAV wrappers. The current installation provides 31 distinct clips and 46 active emitters. Runtime loads them directly; it does not require editor reimport. In navigation mode, **M** toggles music and **N** toggles the ambient bed and positional sounds. Changes to the reload host require restarting the preview once.

The music and ambient bed follow the module defaults. Positioned sounds use the original coordinates, audible distances, approximate relative levels and randomized intervals; the distance curve and overall mix are Godot approximations. Story-dependent changes, environmental reverb, and original scripted state transitions are not reproduced. A listening walkthrough is needed to tune the mix.

WAV loops append a few guard samples copied from the start of the loop, preventing the Godot WAV mixer from reading beyond the PCM buffer at the wrap point. The original clips and their loop durations are preserved.

The central display uses a 0.65-unit sight tolerance because the imported walkmesh collision lies in front of that wall display; the visible overlay remains near the original screen. The front-facing interaction check still applies. Visual fit and selection from the adjacent room need a walkthrough.

A second central screen, `ship_central_right`, sits beside `ship_central` and retains a separate source assignment. Looking directly at either screen prioritizes it for P and E; otherwise the controller selects the nearest visible console. It was moved forward toward the room after visual inspection showed the first placement was inside the wall; the revised fit still needs review.

The window picker normally shows windows owned by regular applications; named windows on other Spaces remain eligible. Use “Show background and helper windows” to include the full discovery list if an application is missing. The filter only changes the picker, not saved-assignment matching. After rebuilding native code, restart the preview.
