# Validation — M0

Date: 2026-11-18. Results apply only to the inspected host and commands below.

## Environment

- macOS 15.7.7, build 24G720; arm64 MacBook Pro, Mac16,5, M4 Max, 16 CPU cores, 64 GB RAM.
- Active developer directory: `/Library/Developer/CommandLineTools`; CLT 16.4.0.0.1.1747106510, Apple clang 17.0.0 (clang-1700.0.13.5), SDK 15.5. `xcodebuild -version` reports that full Xcode is not selected/installed there.
- Godot at `/Applications/Godot.app/Contents/MacOS/Godot`: `4.7.stable.official.5b4e0cb0f`.
- CMake 4.4.4; GNU Make 3.81; default Python 3.15.0; `/opt/homebrew/bin/python3.12` is 3.12.15. No SCons or Godot command on PATH; launcher uses installed app directly.
- Available execution: shell, filesystem, compiler, headless Godot. No connected GUI inspection/control tool. Shell Git and curl cannot resolve github.com; web documentation is accessible separately.
- Initial repository contained only `docs/PLAN.md`; no `.git` or applicable AGENTS.md found in the workspace or ancestor directories. Existing plan preserved.

## Automated results

| Check | Result | Evidence / limit |
| --- | --- | --- |
| Python helper syntax / CLI | PASS | `python3 -m py_compile tools/dev.py`, `python3 tools/dev.py --help` |
| Configuration / source hygiene | PASS | Both authored JSON files parse; authored source and documentation have no trailing whitespace. |
| Parse player, foundation test, native test | PASS (parsing only) | Each `--headless --check-only --script <path>` exits 0 with no script/parse errors; sandbox user-data errors still emitted. |
| Foundation physics | PASS (assertions only) | `--headless --fixed-fps 60 --script tests/foundation.gd` prints `Foundation physics checks: PASS`, exits 0. Tests actual CharacterBody3D motion against floor, console, side/back wall, focus-loss movement stop, and fall recovery. Environmental startup errors still emitted. |
| Main scene headless startup | PASS (scene only) | `--headless --quit-after 120`; exits 0, no script/resource errors. Does not test graphics. Environmental startup errors still emitted. |
| Strict combined `python3 tools/dev.py check` | BLOCKED | Returns 1 on Godot user-data startup errors; intentionally does not suppress them. |
| Apple Objective-C++ + Foundation | PASS | Command below compiled arm64 binary and printed `Version 15.7.7 (Build 24G720)`; this is independent of godot-cpp. |
| Native configure/build | BLOCKED | `python3 tools/dev.py native` detects working CXX/OBJCXX compilers, then FetchContent clone fails: `Could not resolve host: github.com`. No bridge binary produced. |
| Native Godot load/call | NOT RUN | Depends on native build; no inferred compatibility result. |
| GUI launch smoke attempt | BLOCKED | Direct engine launch with `--quit-after 120` exits 134 without output; no observed rendered window. Cause not diagnosed; no GUI acceptance claim. |
| Git status / diff check | BLOCKED | Folder is not a Git repository. |

For direct Godot checks above, `--path . --log-file /Users/jarrett/dev/ebon_hawk/build/<check>.log` was also supplied. Absolute log paths prevent logging outside the workspace. Godot reports inability to create its usual `~/Library/Application Support/Godot/app_userdata/Ebon Hawk Desktop/` and, on scene startup, a `get_system_ca_certificates` condition error. These errors remain visible and are not considered passing checks by the strict helper. An early probe without a log override also crashed while attempting default log output; all supported helper commands supply an absolute log path.

Independent compiler check, from the repository root:

```sh
mkdir -p build
xcrun clang++ -std=c++17 -arch arm64 -mmacosx-version-min=15.0 \
  -framework Foundation tests/macos_toolchain.mm -o build/macos_toolchain
./build/macos_toolchain
```

## Exact local completion commands

Run in a normal macOS Terminal session with GitHub network access:

```sh
cd /Users/jarrett/dev/ebon_hawk
python3 tools/dev.py check
python3 tools/dev.py native
python3 tools/dev.py native-check
python3 tools/dev.py run
```

Expect strict check to exit 0 without ERROR lines, native build to produce `native/bin/libebon_hawk.dylib`, and native-check to print OS/build information followed by `Native load and Objective-C++ call: PASS`. If version checks fail, configure paths using `config/local.example.json`; use the pinned versions rather than silently substituting another release. Native configure can be rerun after network recovery. Full Xcode, export templates, screen-recording permission, and Accessibility permission are not M0 prerequisites.

## Actual GUI acceptance — all NOT RUN

| Local action | Expected result | Status |
| --- | --- | --- |
| Launch placeholder | Lit enclosed room, exactly one labeled console, readable instructions | NOT RUN |
| Observe spawn and look around | Spawn above floor, facing console; no initial intersection; pitch clamped | NOT RUN |
| WASD / diagonal motion | Comfortable first-person movement; no faster diagonal travel | NOT RUN |
| Walk into every wall and console, circle console | Solid boundaries and console; no falling or clipping | NOT RUN |
| Escape, then press WASD and move mouse | Pointer visible and navigation stopped | NOT RUN |
| Left-click game window | Mouse captured; movement and look resume | NOT RUN |
| Cmd+Tab away while holding a movement key; release key; return | Pointer released and motion stops; explicit click resumes with no stuck movement | NOT RUN |
| R after walking and looking around | Original spawn and camera orientation restored | NOT RUN |
| Resize window / Retina view | HUD and console visible, scene usable | NOT RUN |
| Cmd+Q and window close, then relaunch | Normal quit and clean launch | NOT RUN |

After running, record date, engine/OS versions, PASS/FAIL and any errors for each row. Automated results on this Mac do not establish manual macOS GUI validation or user acceptance. M1 capture, input forwarding, menus, and source lifecycle checks have not been implemented or performed.

# M1 implementation session — 2026-11-18

The M0 record above is historical. A Git repository now exists (main branch, no commits; all project files untracked). Root AGENTS.md appeared during the session, was read when discovered, and supplies commit/staging rules; it was preserved. No commit/staging operation was performed. Host/SDK/engine pins are unchanged. No connected GUI control/inspection tool was available.

## Results actually obtained

| Check | Result | Evidence / boundary |
| --- | --- | --- |
| macOS backend compile + link | PASS | `python3 tools/dev.py platform-check` compiles **session.mm** with AppKit, ScreenCaptureKit, ApplicationServices, CoreMedia, CoreVideo and Foundation; `-Wall -Wextra -Werror`, ARC, arm64, deployment 15.0. This does not compile bridge.mm or load Godot. |
| Native ledger / lifecycle | PASS | The same executable tests duplicate downs, normal ups, partial button release, draining keys/buttons, idempotent repeated drain, repeated end/stop, and initial inactive state. No actual injected event delivery is tested. |
| Separate executable permission preflight | PASS (query only) | `capture=0 accessibility=0 listen=0`; no prompts requested. Applies to `build/platform_checks`, **not** to Godot. |
| Script parsing | PASS | Player, mapping, controller, foundation test, coordinate test and native smoke test parse in Godot with no script errors. |
| Production coordinate/ray functions | PASS (assertions) | `tests/console_mapping.gd`: bars rejected, center correct, invalid dimensions rejected, content-pixel offset applied, negative origins, Retina/downscale cancellation, resized/moved bounds, actual placeholder screen/camera ray. Direct invocation exits 0 and prints PASS; system-certificate startup ERROR still emitted. |
| Preserved M0 physics | PASS (assertions) | Direct foundation test exits 0 and prints PASS after controller integration and navigation-action cleanup changes. Same certificate ERROR emitted. |
| Headless main scene | PASS (scene only) | 120-frame startup exits 0, no script/resource errors; certificate ERROR emitted. Does not exercise GUI rendering, shader GPU compilation, picker UI or native extension. |
| Strict combined check | BLOCKED | `python3 tools/dev.py check` parses all scripts, then stops with exit 1 after foundation assertions because Godot emits `get_system_ca_certificates` / `ret != noErr`. Does not silently classify this as success. The previous user-data mkdir errors did not recur. |
| Native GDExtension configure/build | BLOCKED | `python3 tools/dev.py native` again fails cloning godot-cpp: `Could not resolve host: github.com`. Full bridge compilation and dynamic loading remain unverified. |
| Native smoke inside Godot | NOT RUN | No built extension. `native-check` is supplied for load, initial state/permissions, no-source acquisition refusal, and repeated cleanup after the build succeeds. |
| Non-headless Godot launch | BLOCKED | New direct launch with absolute log and `--quit-after 120` aborts, exit 134, without output. Cause not diagnosed; no observed GUI or input result. |
| Python helper / JSON / whitespace | PASS | Helper py_compile; local example/profile JSON parse; authored source whitespace checked. `git diff --check` has no tracked changes to examine; explicit file check used for untracked source. |

The build dependency failure prevents all Godot→native calls. The standalone backend PASS is compiler/link/lifecycle evidence, not capture or input feasibility evidence. No permission was granted by the agent; no target application was driven, and no frame or typed text was logged.

## Exact local build and launch

Use a normal GUI Terminal with GitHub access:

```sh
cd /Users/jarrett/dev/ebon_hawk
python3 tools/dev.py platform-check
python3 tools/dev.py native
python3 tools/dev.py native-check
python3 tools/dev.py check
python3 tools/dev.py run
```

If native compilation reports an error, retain the output; backend-only compilation does not cover the Godot binding conversion code. `native-check` should print M1 OS/build info and `Native load and Objective-C++ call: PASS`; the strict helper must also exit 0 to record a clean pass.

From the running scene:

1. Open a blank **TextEdit** document using macOS. Leave it unminimized on the current Space for the first trial. A selected primary window is the only capture source.
2. Walk toward the console (W for about a second), press **P**. The picker shows capture, Accessibility and listen-event status. Use **Request permissions** if needed.
3. In **System Settings → Privacy & Security**, enable **Screen & System Audio Recording / Screen Recording**, **Accessibility**, and **Input Monitoring** for **Godot**, the application running the scene. Do not grant only the platform-check executable. Restart Godot after grants; press P and Refresh. Confirm all three statuses true.
4. Pick `TextEdit — <document title> [window ID]`, using Capture selected window or double-click. Wait for `live` and an actual changing image on the 3D console. A live image alone is not an interaction pass.
5. Press **E**. The camera should align with the screen and the 3D room must remain visible while the target becomes active behind it. The hint must name the target and release key. Input must stop on failed/ambiguous focus matching.
6. Perform the matrix below. **Right Control / Escape** releases; choose **F12** in the picker if appropriate (Fn+F12 may be needed). Test the actual keyboard. Cmd+Q is reserved for Godot quit; Cmd+Tab releases before app switching. After release, click Godot to resume navigation. R resets spawn only in navigation.

Repeat choosing Chrome and Terminal through P; this is still one source at a time, not M2. After restoring/resizing a source, wait for a live compatible frame and re-enter with E. A focus/geometry failure should release immediately instead of delivering to an unverified window.

Direct independent Godot checks when diagnosing a strict-check startup error:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --log-file /Users/jarrett/dev/ebon_hawk/build/m1-mapping.log \
  --script tests/console_mapping.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --log-file /Users/jarrett/dev/ebon_hawk/build/m1-foundation.log \
  --fixed-fps 60 --script tests/foundation.gd
```

Record assertions and environmental errors separately, as done above.

## Native acceptance matrix — no passes inferred

Candidate app versions read from local Info.plist files: TextEdit **1.20**, Chrome **157.0.8103.79**, Terminal **2.14**. These applications were not driven. Test with harmless temporary documents/pages and record the actual versions/date/results. For every successful row, confirm the room stays visible and the exact chosen window receives input. If an app opens over the room, the visibility criterion fails.

| Scenario / concrete local action | Required observation | Result in this session |
| --- | --- | --- |
| Picker and permissions | App/title/ID labels, actionable denied state, refreshed grants | NOT RUN (GUI/build blocked) |
| Live TextEdit window | Continuous actual changes on the console, including when covered by Godot | NOT RUN |
| TextEdit type/select/copy/paste/undo | Type a test sentence, drag-select part, Cmd+C, move caret, Cmd+V, Cmd+Z; changes in chosen document only | NOT RUN |
| Text input sources | Repeat text entry with English and Russian if available; choose the source before entering console mode | NOT RUN |
| Double click / right click | Word selected; record whether context menu is included and operable | NOT RUN |
| Drag then move outside console and release | Selection/drag stops; no held target button; bars never receive pointer downs | NOT RUN |
| Chrome scroll/link | Scroll a page; click an ordinary link through the console; result remains live | NOT RUN |
| Terminal | Enter `pwd` and Return; correct output in chosen Terminal window | NOT RUN |
| Resize / move / display scale | Release, resize/move source, wait for new live frame, re-enter; clicks land correctly at corners/center on Retina and any other available display | NOT RUN |
| Source resized externally while interacting | Input releases with reason before stale coordinates are used; explicit E recovery after live frame | NOT RUN |
| Reserved release | Press actual Right Control, F12 alternative, and Escape; immediate return, no target key leakage; click resumes WASD | NOT RUN |
| Held modifier/button cleanup | Exit while Shift/Cmd or drag is held; next ordinary target input is not stuck; repeat after focus/source loss | NOT RUN |
| Quit / app switch | Cmd+Q quits Godot cleanly; Cmd+Tab releases before ordinary switching | NOT RUN |
| Exact-window focus | With two windows in one app, select one, verify only it receives typing; changed AX focus stops routing | NOT RUN |
| Native menu (TextEdit Format or context menu) | Try opening/using one native menu through its available UI; record if absent from primary capture or if focus guard releases | NOT RUN |
| File dialog (TextEdit Cmd+O; Cancel) | Attempt Open through console; record whether panel/sheet appears in capture, focused AX identity, release reason, and recovery | NOT RUN |
| Occlusion | Cover source with Godot and another ordinary window; capture and selected-target input still work without exposing source above room | NOT RUN |
| Minimize / restore | Clear paused/minimized/unavailable state, no forwarding; restored source becomes live and can explicitly re-enter | NOT RUN |
| Source closed / app quits while key or drag held | Recoverable source state and held-input release; no crash or arbitrary reassignment | NOT RUN |
| Space / fullscreen / Stage Manager if enabled | Move source to another Space; record activation/room visibility/capture/input behavior, do not infer from capture alone | NOT RUN |
| Permission revoked | Revoke grants in settings during capture/interaction; usable navigation and actionable status; no continued forwarding | NOT RUN |
| Tap/heartbeat failure | In a controlled local diagnostic session, interrupt polling; input ownership drops and held inputs release; record actual delivery | NOT RUN |

Menu/dialog behavior was investigated at the API/implementation boundary: the stream captures one primary window, while a separate focused AX window fails the identity guard. No native menu or file-dialog workflow was actually exercised. Predicted limitations are in architecture.md; these rows remain open. M1 is **incomplete** until required real end-to-end workflows pass or their concrete failures are resolved. M2 has not begun.
