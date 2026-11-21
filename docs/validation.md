# Validation

## M1 final acceptance — 2026-11-20

The user accepted all eight M1 criteria on 2026-11-20. The table follows
the eight original acceptance criteria in docs/PLAN.md. Earlier entries
below preserve the sequence of experiments.

| Original criterion | Result at checkpoint |
| --- | --- |
| Editor sentence, selection, copy/paste and undo | Pass by user report. The user reported that text editing worked except for held keys, then confirmed the held-key fix. Obsidian Cmd+C/V was also confirmed separately. The editor used for the final check was unspecified. |
| Browser scroll and link activation | Pass. User confirmed Chrome scrolling and link activation through the console on 2026-11-20. |
| Drag-select and release without stuck input | Pass. User confirmed drag and release on 2026-11-19. |
| Terminal command | Pass. The user ran pwd through the console and saw live output. Held J and Backspace repeat are now user-verified. |
| Correct clicks after moving or resizing | Pass by user report for geometry and targeting on 2026-11-19. Display configurations were unspecified. |
| Room visible during operation | Pass. User confirmed the Terminal workflow and supplied a view of Discord on the console inside the room. |
| Release to navigation without held input | Pass. The user confirmed all release and recovery items work. Earlier live checks also confirmed normal navigation and re-entry. |
| Document menus, dialogs, minimized windows and Spaces | Complete by user sign-off. The user confirmed all menus work correctly. Earlier examples include Obsidian Cmd+O and the fixture context menu. The final report did not itemize file-panel, occlusion, minimization or Spaces observations. |

Before the final fix, the live held-key test produced a single character. The session
log reported a 0.5 s delay, a 1/12 s interval, 66 native repeat posts and
zero fallback events. The revised delivery path posts ordinary up/down pairs
for editing-key repeats. The user confirmed the fix on the actual Mac.

The approved validation plan also calls for same-app two-window focus isolation,
permission loss, app switching and quitting, and failure recovery. The native
watchdog runs inside Godot. SIGSTOP suspends that thread too, so it cannot
release held input during a whole-process stop. Recovery after the process resumes is distinct from cleanup during suspension.

At this checkpoint all four development checks passed on macOS 15.7.7 arm64
with Godot 4.7, and the mouse fixture compiled. The cursor appearance issue
is separate from the functional acceptance rows.


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

The M0 record above is historical. At initial M1 inspection, a Git repository existed on main with no commits and all project files untracked. Git metadata was subsequently updated externally during the session. Root AGENTS.md appeared during the session, was read when discovered, and supplies commit/staging rules; it was preserved. No commit/staging operation was performed. Host/SDK/engine pins are unchanged. No connected GUI control/inspection tool was available.

## Initial M1 results (historical; superseded where noted below)

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
| Native smoke inside Godot | BLOCKED / NOT RUN | `native-check` was invoked and refused with `Run python3 tools/dev.py native first.` No built extension. `native-check` is supplied for load, initial state/permissions, no-source acquisition refusal, and repeated cleanup after the build succeeds. |
| Non-headless Godot launch | BLOCKED | New direct launch with absolute log and `--quit-after 120` aborts, exit 134, without output. Cause not diagnosed; no observed GUI or input result. |
| Python helper / JSON / whitespace | PASS | Helper py_compile; local example/profile JSON parse; authored source whitespace checked. An explicit file check covered source while untracked; the final `git diff --check` also passes after external Git metadata updates. |

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
| Picker and permissions | App/title/ID labels, actionable denied state, refreshed grants | NOT RUN (GUI trial pending) |
| Live TextEdit window | Continuous actual changes on the console, including when covered by Godot | NOT RUN |
| TextEdit type/select/copy/paste/undo | Type a test sentence, drag-select part, Cmd+C, move caret, Cmd+V, Cmd+Z; changes in chosen document only | NOT RUN |
| Text input sources | Repeat text entry with English and Russian if available; choose the source before entering console mode | NOT RUN |
| Double click / right click | Word selected; record whether context menu is included and operable | NOT RUN |
| Drag then move outside console and release | Selection/drag stops; no held target button; bars never receive pointer downs | NOT RUN |
| Chrome scroll/link | Scroll a page; click an ordinary link through the console; result remains live | PASS — user confirmed scrolling and link activation on 2026-11-20. |
| Terminal | Enter `pwd` and Return; correct output in chosen Terminal window | PASS — user verified 2026-11-18, with live console output. Follow-up: single backspace works, held backspace does not repeat; double-click word selection fails; copying text from Terminal fails. See follow-up findings below. |
| Resize / move / display scale | Release, resize/move source, wait for new live frame, re-enter; clicks land correctly at corners/center on Retina and any other available display | NOT RUN |
| Source resized externally while interacting | Input releases with reason before stale coordinates are used; explicit E recovery after live frame | NOT RUN |
| Reserved release | Press actual Right Control, F12 alternative, and Escape; immediate return, no target key leakage; click resumes WASD | PARTIAL — user verified release and click-to-resume WASD; exact key unspecified, alternatives/key-leakage test open |
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


## Native build follow-up — 2026-11-18

The user downloaded the pinned godot-cpp dependency and encountered a fatal missing `godot_cpp/classes/os.hpp`. The authored build profile enabled only RefCounted; godot-cpp's own `src/core/print_string.cpp` includes OS unconditionally. Added OS to `native/build_profile.json`; no dependency source edits or clean-cache deletion were needed.

- `python3 tools/dev.py native`: PASS, exit 0; generated OS bindings, compiled bridge.mm and session.mm, linked `native/bin/libebon_hawk.dylib`. Third-party unused-parameter warnings remain nonfatal.
- `python3 tools/dev.py native-check`: native assertions PASS; Godot loads/registers the class, checks initial state/permissions and no-source refusal, exercises repeated cleanup, and calls Objective-C++. Strict command exit 1 because the separate `get_system_ca_certificates` startup ERROR persists.
- `git diff --check`: PASS.

The `float_64` generator label means single-precision float bindings for a 64-bit architecture, as confirmed in the downloaded binding_generator.py (`real_t + "_" + bits`); it does not mean double-precision Godot. The CMAKE_MSVC_RUNTIME_LIBRARY message is generic dependency configuration output, not a macOS error. No GUI capture/input acceptance was performed during this fix.


## Clean automated verification follow-up — 2026-11-18

Ran the commands directly and resolved the remaining automated failures:

- `python3 tools/dev.py native`: PASS, exit 0. Added `GODOTCPP_SYSTEM_HEADERS=ON` to retain warnings for project code while excluding warnings from godot-cpp headers. Final build log (`build/native-verification.log`) has no warning/error diagnostics and produces the dylib.
- The native macOS certificate query uses `SecTrustCopyAnchorCertificates`; it fails in this execution environment. Configured ignored `override.cfg` with `network/tls/certificate_bundle_override="/etc/ssl/cert.pem"`, using the installed PEM trust bundle. No error filtering or TLS-verification disabling was added. This bypasses the failing Keychain query, so custom Keychain trust overrides are not used by this local configuration. Reproducible example: `config/macos-ca.example.cfg`; merge with existing overrides rather than overwriting them.
- `python3 tools/dev.py native-check`: PASS, exit 0, no ERROR lines.
- `python3 tools/dev.py check`: PASS, exit 0, no ERROR lines. Includes script parsing, foundation physics, console coordinate/ray checks, and headless scene startup.
- `python3 tools/dev.py platform-check`: PASS, exit 0; preflight remains capture=0/accessibility=0/listen=0 for that test executable.
- Non-headless launch with `--quit-after 120`: still BLOCKED, exit 134. An existing Godot crash report records SIGABRT in `_RegisterApplication` → AppKit menu-bar initialization → `NSApplication init`, before scene execution. This is evidence of an application-registration failure, not a completed GUI test or a proven diagnosis of its underlying cause.

These results supersede earlier automated build/certificate blockers. All real-window acceptance rows remain NOT RUN; no GUI success is inferred from the clean headless checks.

## Terminal input follow-up — 2026-11-18

User reports that Terminal accepts typed text and single backspace, but holding backspace does not repeat. Double-click word selection fails, and copying text from Terminal fails. A follow-up drag-selection attempt also produced no highlight. The user also reports ordinary clicks do not register in Obsidian, confirming a general pointer-forwarding failure across applications. These observed GUI failures keep M1 open. The code retains Quartz keyboard repeat and mouse click-state fields when copying events, so the cause is not yet established. Camera FOV now narrows to 45 degrees during console interaction and restores on release, making the captured window larger while preserving the navigation view. Copy may depend on a text selection; the user then tried dragging across Terminal text, but no highlight appeared. After trying the new interaction zoom, recheck a click and drag selection in Obsidian or Terminal. The interaction hint reports pointer events submitted to the target and events rejected locally, which separates local filtering from target-side delivery. The fixture counters confirm AppKit receives events in its own view. Key-repeat remains a separate open failure. No fix or pass is claimed until these behaviors are verified.

## Native pointer receiver fixture — 2026-11-18

The normal session-stream pointer trial below FAILED user validation: the physical cursor was repeatedly pushed toward the screen edge. Remapped system pointer events appear to feed back into physical-position sampling. Reverted session-stream posting, desktop hit-testing, and Godot mouse passthrough; restored process-targeted pointer delivery and cleanup. Rebuilt the extension and passed native smoke. The original app-specific mouse-delivery failure remains open. The running game must be restarted to unload the failed trial.

Pointer delivery trial: mouse/scroll events now enter the normal session event stream at the mapped source position. Godot ignores mouse hits while interacting and restores its prior setting on exit. Before posting an in-bounds pointer event, the native backend checks that the selected source is the first non-Godot visible window at that point; otherwise it releases. Button cleanup uses the same session stream. Keyboard delivery remains process-targeted. Native build, platform checks and native smoke pass; real Obsidian clicking/dragging and physical cursor behavior need user verification. This replaces the earlier process-targeted pointer approach for this trial.

Built a minimal AppKit window that visibly counts received mouseDown, mouseUp, mouseDragged, rightMouseDown, scrollWheel, and keyDown callbacks. It stores no key characters and writes no captured content. Build with `python3 tools/dev.py mouse-fixture`, then run `./build/mouse_fixture`. Close the previous fixture first so the rebuilt executable is used. In the Ebon Hawk picker choose “Ebon Hawk Mouse Fixture”, wait for live, enter with E, and compare the fixture counters with the console's posted/not-posted counters.

If console pointer-posted increases while fixture mouse counters stay zero (and keyDown increases for a key press), the target process is not dispatching the posted mouse events. If fixture events arrive but last view points are wrong, investigate target coordinate mapping. If events are marked not posted, investigate the console bounds/event-pair filters. Close the fixture window to exit. User verification: the fixture received mouseDown=7, mouseUp=7, mouseDragged=84, rightMouseDown=2, scrollWheel=6, and keyDown=5 through the console. Its app was active and its window key/main; firstMouse checks remained 0. This rules out a blanket event-posting failure and makes first-mouse rejection unlikely in this fixture. It does not prove clicks hit the intended controls in Terminal or Obsidian. The fixture now includes a real NSButton and selectable NSTextView. It also reports text-view keyDown/flagsChanged counts, Command+C/V key-equivalent counts, actual copy/paste action counts, the latest Command flag, text length, and selection length; no typed or pasted text is displayed or stored. The first shortcut trial used a fixture without an Edit menu, so its no-op result was a harness limitation. The rebuilt fixture now has standard Edit menu bindings; rerun shortcuts there before drawing conclusions about target keyboard delivery.

## Reliability diagnostics and latest automated checks — 2026-11-18

Status now reports selected window ID/PID, the latest AX focus-match result, source state, capture dimensions and scale metadata, pointer events posted/not posted, and the last input-release reason. Following the user report that events post but do not register, forwarded and cleanup events now also carry the selected target PID in the Quartz event metadata; a native assertion covers setting that field. The interaction hint shows pointer counters; not posted includes events rejected by bounds or unmatched drag/up events. Posted means submitted to the target process, not acknowledged by it. The system does not record typed text or frame pixels. On the first valid capture frame, the starting message changes to Capture live. The native smoke test checks that these diagnostic fields remain present.

After adding target-PID event metadata, python3 tools/dev.py native, native-check, platform-check, and check all pass. The GUI delivery result is not yet verified; restart the game process once to load this non-reloadable native extension and retry a harmless click. The platform permission preflight is query-only and reports capture=0, accessibility=0, listen=0 for its separate test executable; it does not indicate the grants on the user's Godot application.

Agent GUI execution is unavailable in this environment. Terminal is user-verified as recorded below. For the next short manual batch, use TextEdit: type one sentence; click to place the caret; double-click a word; drag-select a phrase; copy, click elsewhere, paste, then undo. Report whether each action affected the selected TextEdit window, whether the room stayed visible, and any release or focus change.

Source evidence for the certificate workaround: [Godot macOS trust-store implementation](https://github.com/godotengine/godot/blob/4.7/platform/macos/os_macos.mm) and the installed engine's certificate_bundle_override setting. The fix supplies a trusted CA bundle rather than relaxing certificate validation.


## User-confirmed Terminal end-to-end results — 2026-11-18

Evidence: the user supplied a screenshot of the real Terminal displayed on the 3D console, reported E activation and typing, then confirmed all three follow-up checks:

1. PASS — type `pwd`, press Return, and see output update on the console.
2. PASS — release using Right Control or Escape, click Godot, and resume WASD navigation.
3. PASS — re-enter with E and confirm no keys/modifiers remain stuck during this normal cycle.

These are user-performed macOS GUI checks, not agent-observed automated tests. The room remains visible in the supplied capture. The exact release key used was not specified; this does not validate every alternative key, explicit held-modifier/button release, abnormal exits, or source-loss cleanup. Existing inspected host/app versions provide context; versions were not independently re-reported for this user test.

This supersedes earlier NOT RUN statements for Terminal capture/typing/command output and the normal release/re-entry cycle. Editor/browser, mouse actions, geometry changes, menus/dialogs, occlusion/minimization, Spaces and failure scenarios remain open. M1 is partial; M2 has not started.

## One-click routing trace

Restart the standalone game, enter a live console, and left-click once.
The hint and Godot output show separate Down and Up lines for the latest click.
Each posted phase includes its route, the desktop hit window and selected
window IDs, and the mapped Quartz point. A local rejection shows its reason.
Mouse motion leaves these lines in place.

For a direct post, compare the hit window ID and owner with the selected
window. A direct post can bypass the annotated session tap. For a session
post, “seen” means a listen-only annotated session tap saw the tagged
event with the matching phase and timestamp. Application receipt still
requires a separate observation. “Unseen” means no match so far.
“Unavailable” means the observer could not provide a reading.

The live trace recorded down/up pairs 93/94 and 113/114 using direct delivery.
Both phases hit Godot window 69591 while window 68877 was selected. Both
showed downstream seen. This run exercised the PID fallback. The revised
hit test checks beneath the floating click-through Godot window when it is
the first hit. The trace labels this second result “beneath Godot”.
A session post still requires the selected window at that point. Live
interaction with the revised routing remains to be verified.

Discord hover was visible during fast mouse movement, followed by the cursor
being pushed off the console. The latest log contained a down rejected outside
content and an up rejected without a held button. Successful clicking and
steady hover are still unverified.

The next build requests relative mouse motion before activating the target
and draws one orange + at the logical pointer. With Discord selected, move
the + slowly onto a message and stop. Check whether the + and the message
highlight stay in place, whether a click operates a control, and whether
Escape restores normal desktop cursor movement and visibility.

User GUI result: clicks now operate controls in the selected window. The
desktop cursor remained visible alongside the orange console pointer.
The cursor visibility change enables background cursor control for the
Godot connection during interaction and restores the prior setting on
release. Verify orange-only aiming and return of the normal cursor on exit.

### M2 initial checks — 2026-11-21

- PASS: `python3 tools/dev.py check` (including selector ambiguity and missing-source checks).
- PASS: `python3 tools/dev.py native`, `native-check`, and `platform-check`.
- NOT RUN: live dual capture, two windows of one app, input switching, restart restoration, source loss/reopen, and cleanup in the GUI. The command-line preflight reported capture, Accessibility, and Input Monitoring permissions unavailable. These results do not establish M2 acceptance.

### M2 user acceptance — 2026-11-21

The user reported that everything works and requested that M2 be marked complete. This supersedes the open acceptance status above. Individual live scenarios and their results were not separately reported.

### M3 initial asset checks — 2026-11-21

- PASS: Two extraction runs yielded identical hashes for all 177 extracted layout/model/walkmesh/texture files; 16 rooms and 128 texture/lightmap names, no missing sources.
- PASS: Blender 4.2.23 and KotORBlender `afae04c9172f30ab765891315d9d11224ab57426` imported and exported the layout. Fifteen walkmesh objects were imported. The exporter warned that some vertex colors were not exported.
- PASS: Headless Godot scene loads and finds collision below the central cabin spawn.
- NOT RUN: GUI visual inspection, lightmap/material fidelity, full room navigation, wall/door collision coverage, and visual acceptance. The sixteenth source walkmesh (`003eboq`) has zero faces. The exported visual GLB contains 34 images, so the 94 extracted lightmaps are not embedded.

### M3 follow-up — 2026-11-21

- The user confirmed the Blender assembly looks accurate, as recorded in the approved plan. This is separate from Godot acceptance.
- Extraction reran with 16 rooms and 128 texture/lightmap names, with no missing sources. Blender 5.3.0 and the pinned KotORBlender revision exported 899 lightmapped objects with two recorded exceptions (`Box18`, `Box19`). The required Blender 4.2.23 rebuild has not been repeated.
- Headless Godot loaded the recorded diffuse textures, lightmaps, and UV2 arrays. The spawn floor, reset transform and camera, a second floor, and one nearby wall were checked. These checks do not render the shader or demonstrate traversable routes.
- At the `003eboq` layout origin, a vertical collision ray found no surface. The zero-face walkmesh and this ray do not establish whether a floor or wall is needed there; visual and navigation inspection remain open. No authored collision was added.
- NOT RUN: Godot GUI inspection and walkthrough through cockpit and console-room routes, transparency and lighting review, doorway clearance, and recovery while walking. M3 remains incomplete.

### M3 furniture collision follow-up

- The user walked through the Godot preview and reported that the ship looks and feels like the Ebon Hawk, walls were solid and doors open, but furniture including the central table lacked collision. They also observed distance-dependent translucency and inconsistent lighting; those rendering issues remain open.
- Inspected the source assembly for named furniture and added a separate collision export for 16 selected meshes. A ray and a player-capsule movement test hit the central hologame table; a ray and capsule movement test cross one central doorway. Existing floor and wall checks still pass.
- The selected furniture is not a complete automatic classification of the ship, and the additional shapes and other doorway and console approaches have not been walked through in Godot. M3 remains incomplete.

### M3 cockpit collision follow-up

- The user reported that the furniture pass was thorough in their walkthrough; the remaining missing objects were the cockpit chairs, instruments, and pilot controls.
- Added the cockpit chair, instrument-panel and central-control source meshes to the separate collision export. Headless ray checks hit each selected mesh, and a player-capsule check crosses the cockpit entrance. A live walkthrough of these new additions remains outstanding.

### M3 curved chair panel

- The user confirmed the cockpit additions and identified the curved panel behind three central-room chairs as the last missing collision. Added its side and top source meshes to the furniture export; a headless ray hits the panel, and existing doorway checks remain in place. The panel addition has not yet been checked in a live walkthrough.

### M3 collision acceptance

- The user accepted the collision work as complete after the curved panel addition. This supersedes the open collision status above; the final acceptance did not separately describe a live test of the panel. Rendering and the other M3 work remain open.

### M3 material transparency investigation

- The source TXI metadata identifies several metal wall and floor textures as environment-mapped. Their alpha channels encode reflectivity, but the earlier extraction dropped the metadata and the preview treated that alpha as transparency.
- Extraction now retains TXI metadata. The rebuilt local material manifest classifies 894 lightmapped objects as opaque and five as blended; the shader also supports cutout and additive modes. The ship check confirms the metal wall classification and a transparent net sample, loads the materials and runs the collision checks. The general project checks pass.
- The shader still does not reproduce environmental reflections or bump mapping. Texture export color values and lightmap brightness need comparison against the source and Blender; the transparency changes and lighting have not been inspected in the Godot GUI. M3 remains open.

### M3 material acceptance

- The user reviewed the updated preview, reported that it looked much better, and accepted the subtle remaining differences from the game as good enough for the MVP. This supersedes the visual-inspection status above. Environmental reflections and bump mapping remain known fidelity limitations; M3 as a whole remains open.

### M3 toolchain and checklist reconciliation

- Blender 5.3.0 build `02f0899d78e3`, used for the successful local rebuild, is now the documented pin. The earlier 4.2.23 requirement above is superseded.
- Asset discovery, assembly, extraction/export workflow, material and collision work, and spawn/reset implementation are complete. Spawn/reset has automated coverage; individual live reset observations were not reported.
- The documented pipeline has not been verified on another local setup. That acceptance criterion remains open.

### M3 completion

- The user restricted the reproduction requirement to this Mac, where the documented pipeline was rebuilt. Cross-computer verification is no longer required. With the user's collision and MVP appearance acceptance and the completed implementation tasks, M3 is complete. Earlier open-status statements are superseded; known material limitations and the lack of a separately reported live reset test remain recorded above.

### Ship development reload

- Headless reload checks pass for the T shortcut, deferral while input is locked, and preservation of player position and camera orientation. Existing ship and general project checks pass.
- In an isolated project copy, an edited player script was detected and its new code ran in the reloaded scene; a subsequent invalid script was rejected by validation while the preview stayed running. The command was also exercised against a running headless preview.
- The fullscreen Mac GUI, actual captured-window interaction, graphics-driver shader compilation, and live console-session restoration have not been tested with reload. Native and reload-host changes require restarting the preview.


## M4 ship consoles — 2026-11-21

The ship now has cockpit, central, and medbay screen overlays. `python3 tools/dev.py check`, `ship-check`, and `reload-check` pass headlessly. The ship check covers three unique IDs, floor support, approach capsule clearance, line of sight, and aligned camera poses; the placeholder and selector tests remain in the project check. The preview launches with the Mac graphics renderer. This is not evidence of readable text, visual fit, actual window interaction, distinct input ownership, restored real assignments, or a live GUI reload. Those walkthrough results remain pending; M4 is not marked complete.

On 2026-11-21 the user reported that all three consoles and the requested live reload checks work. Detailed individual results were not supplied. The user requested further placement adjustments, beginning with the cockpit console.


## Ship audio prototype — 2026-11-21

Extracted the 003EBO music and ambient bed plus 31 distinct clips covering 46 active sound emitters from the local installation. `ship-check` verifies that the generated clips load, emitters instantiate, and M/N toggle the music and ambience; reload validation exercises the scene replacement. Headless checks do not establish audible balance, room transitions, loop quality, or similarity to the original. User listening verification is pending.


### M4 interaction regression — 2026-11-21

The user confirmed distinct assignment, monitor switching, readability, and reassignment, but reported that E refused input because Accessibility matching failed. Matching now prefers an exact native window ID when available and otherwise requires the existing unique bounds-and-title match. Failures report an Accessibility error or match counts without recording window titles. The HUD suppresses stale source messages when no console is nearby. Native build, platform checks, and project checks pass; the fix still requires a live retry after restarting the preview.


### Cross-Space interaction follow-up (2026-11-21)

Window discovery now checks Accessibility windows, main and focused windows,
and window-role children. Failed discovery logs only attribute error codes,
counts and match counts; it does not log titles or content. Compare the first
(pre-activation) entry with retry entries after activating the fixture. The
public Accessibility attributes may still omit windows in other Spaces; if
the selected window cannot be identified and focused, interaction times out.
No private cross-Space enumeration is used.

Native platform/build, project (including placeholder-room foundation), ship,
and reload checks passed in this environment. Permission preflight reported
Screen Recording, Accessibility, and Input Monitoring unavailable to the test
process. The interactive fixture matrix (same/other Space, ordinary/maximized,
two windows, clicking, typing, resize, focus loss, release, and ship visibility)
therefore remains unverified. M4 acceptance remains open.


### Live console interaction acceptance — 2026-11-21

The user reported that everything in the requested console verification
passes, including the cross-Space and two-window checks. Individual app
versions and observations were not supplied. This completes the previously
reported live M4 interaction check; it does not establish the separate M5
native dialog, popup, and failure-recovery matrix.

### M5 recovery follow-up — 2026-11-21

Capture loss, source resize, and other release paths now cancel a pending
interaction attempt. The retry also checks capture state and required
permissions before seeking focus. Native build, native smoke, platform,
project, ship, and reload checks passed; these checks do not simulate a
capture failure during acquisition. Live failure recovery and native
dialog/popup workflows remain unverified for M5.

### M5 temporary windows and recovery — 2026-11-21

The task picker includes otherwise-filtered windows belonging to the
assigned process and does not persist the temporary selection. Return uses
the original window ID and process, and refuses substitution if unavailable.
The automated picker test checks the process filter; existing selector tests
cover missing and ambiguous saved sources and the input ledger covers held
input release. These are not end-to-end acquisition race tests.

The native build, platform checks, project checks, ship checks, and reload
checks pass. The platform test process reports all three permissions absent.
The following separate Mac GUI observations remain **NOT RUN**: editor open
dialog, editor save dialog, native menu, browser popup, terminal interaction,
source close/reopen, minimize/restore, resize, focus change, permission denial,
and permission revocation. For each, record app/version, ship visibility,
exact input target, and recovery before accepting M5. No app-specific
exceptions have yet been established.
