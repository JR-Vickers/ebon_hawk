# Status — 2026-11-20

**M1 complete.** The user accepted all eight one-window criteria on 2026-11-20, confirming release and recovery and correct menu behavior.

Current automated results:

- Full native extension build: PASS, exit 0, no compiler warnings in the final build. The binding profile includes OS for godot-cpp logging, and dependency headers are treated as system headers while project warnings remain enabled.
- Godot native smoke: PASS, exit 0; class registration, initial state/permissions, no-source refusal, repeated cleanup, and Objective-C++ call.
- Full `tools/dev.py check`: PASS, exit 0; script parsing, M0 physics, coordinate/ray assertions, and headless scene startup.
- Standalone macOS backend compile/link/lifecycle/input-ledger checks: PASS.

The certificate startup error was resolved locally using ignored override.cfg with `/etc/ssl/cert.pem`. A reproducible example is in config/macos-ca.example.cfg. TLS verification and strict error detection remain enabled. Dependency download/build and certificate errors are no longer blockers in this workspace.

Live checks on the user's Mac covered Terminal command output, text editing and held keys, clicks and drags, Chrome scrolling and links, targeting, and release back to navigation with the room visible.

See the [final acceptance record](validation.md) for the per-criterion results and earlier diagnostic history.

## M2 complete — 2026-11-21

Two placeholder consoles now have separate capture sessions, shared interaction control, saved logical selectors, and quality settings. Automated checks and the native build pass. The user reported that everything works and accepted M2 on 2026-11-21. Detailed individual live test results were not supplied.

## M3 complete — 2026-11-21

Located the KOTOR2 GameData installation and identified layout `003ebo` with 16 room models. The user confirmed the Blender assembly looks accurate. The extraction manifest reports 128 referenced textures/lightmaps and no missing source files. The current export supplies Godot with lightmaps for 899 objects; two objects have missing material inputs. Blender imported 15 walkmesh objects; the sixteenth source walkmesh (`003eboq`) has zero faces. The documented toolchain pins the successfully used Blender 5.3.0 build. The user limited the reproduction requirement to this Mac, where the pipeline was rebuilt.

The user walked through the Godot preview: the ship looks and feels right, walls were mostly solid and doors open, but furniture lacked collision and some materials became translucent with distance. Following additions for furniture, cockpit controls, and the curved chair panel, the user accepted the collision work as complete. Automated checks cover the table, panel, cockpit objects, and doorway clearance. After the transparency fix, the user reported the appearance was much better and accepted the remaining subtle differences from the game for the MVP.


## M4 accepted; M5 underway — 2026-11-21

The user reported all requested live console and cross-Space checks passed.
The next milestone covers native dialogs, popups, source and permission
failures, and recovery; the separate M5 acceptance matrix remains open.

M5 has a temporary same-process window picker and recovery changes under
test. Its live workflow and failure matrix is not yet demonstrated, so M5
remains open.
