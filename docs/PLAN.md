# Ebon Hawk Desktop — Implementation Plan

Status: M1 prototype implemented; native build/load and automated checks pass with local CA configuration. Terminal interaction/release/re-entry are user-verified; remaining M1 GUI acceptance is open (2026-11-18). M2 has not started. See docs/status.md and docs/validation.md.
Created: 2026-11-18.
Target user: Jarrett Vickers, using an Apple Silicon MacBook Pro M4 Max.

## 1. Product goal

Build a locally running macOS application in which the user can walk around the Ebon Hawk from **KOTOR2** and use its computer consoles to interact with real windows on the same Mac.

Each console can be assigned a different window. For example, a cockpit console could show a browser, an engineering console a terminal, and another console an editor. These are live, usable application windows, with the real application state and files behind them.

The primary experience is:

1. Launch the application and enter the ship.
2. Walk to a console and activate it.
3. The camera aligns with a readable view of its screen.
4. Mouse and keyboard input operate the assigned Mac window.
5. A reserved release key returns control to ship navigation.
6. Walk to another console and continue working in its assigned window.

The ship must remain visible while interacting. Opening the real application over the ship and switching away from the environment does not fulfill the interaction requirement.

The original KOTOR2 visual style is desirable. Prioritize a recognizable, coherent interior, readable screens, responsive interaction, and dependable behavior over a graphical remake.

## 2. Scope and working defaults

| Area | Initial decision |
| --- | --- |
| Platform | Native macOS application, Apple Silicon first |
| Development and acceptance machine | User's Mac; record its actual macOS version |
| Environment | KOTOR2 Ebon Hawk interior |
| Navigation | First-person mouse and keyboard; adjustable sensitivity |
| Console use | Explicit activation, camera alignment, visible release hint |
| Sources | Individually selected windows from applications on the same Mac |
| Assignments | Editable and persistent per console |
| Concurrency | Several visible live screens; one receives input at a time |
| Rendering | Godot 4 stable, pinned to a tested release |
| Native integration | ScreenCaptureKit and appropriate macOS input/window APIs |
| Assets | Extract/import from a user-supplied KOTOR2 installation |
| Distribution | Local development build followed by a launchable local .app |
| Settings | Local configuration; adjustable graphics and capture quality |

Full-desktop mirroring may later be another source type. It is not a prerequisite for per-window consoles. VR, multiplayer, remote computers, independent virtual desktops, character AI, combat, and a modern asset remake are outside this implementation's required scope.

These defaults support implementation without a long preliminary questionnaire. Discover local paths and tooling where possible. Request only missing information that actually blocks the next dependent step.

## 3. Critical feasibility questions

The major uncertainty is **input and application focus**, not screen capture or ship rendering.

ScreenCaptureKit can capture individual windows, including occluded windows. Apple's documentation describes single-window capture as display- and Space-independent; minimized windows pause output. This is a foundation for display, not proof that the same windows can be fully controlled while Godot remains visible.

Resolve these questions with a small working prototype:

- Can the real Godot application remain visible while the chosen target receives mouse and keyboard events?
- Can input reach the correct window when the application owns multiple windows?
- Does the approach work with representative browser, terminal, and editor applications?
- How are native menus, popup windows, sheets, and file dialogs displayed and controlled?
- What happens when a target is resized, moved, closed, minimized, or moved between Spaces?
- Can the app reliably leave interaction mode, including on focus loss or an integration error?

Important distinctions:

- Capturing a window does not focus it or forward input to it.
- Posting an event to an application process does not by itself identify one window in that process.
- Rendering a 2D Godot UI in 3D does not provide access to native applications.
- A selected window may have auxiliary windows that are absent from its primary capture.
- Keeping a rendered window above a target does not, by itself, solve input focus.

Do not treat a successful API call, a live screenshot, simulated content, or one application-specific workaround as proof of the entire interaction design.

## 4. Execution rules for Codex

1. Inspect the current repository and applicable AGENTS.md instructions before editing. Preserve existing work.
2. Implement in small, working increments following the milestones below. Continue through successful milestones without requesting routine reconfirmation.
3. Test the hardest native behavior before investing substantially in environment polish.
4. Record architecture decisions, observed limitations, and exact validation results as work progresses.
5. Keep the placeholder scene runnable after the ship scene is added. It is the integration test environment.
6. Distinguish implemented, automated-tested, Mac-tested, and user-accepted states. Never infer native success from Linux builds or mocks.
7. If native feasibility is blocked, preserve a reproducible demonstration, report the specific failure, and continue useful independent work. Do not silently replace the requested experience with a VM, another computer, view-only screens, or switching away from the ship.
8. Ask for user input when a missing asset path, permission grant, local test, or product-changing decision is genuinely necessary. State precisely what is needed.
9. Treat project completion as the final acceptance criteria, not merely producing a build or an attractive scene.

## 5. Architecture

### 5.1 Preferred implementation

Use Godot for rendering, navigation, console interaction, settings, and source assignment. Start with GDScript for ordinary game/application logic.

Prefer a small macOS native extension using Godot's GDExtension mechanism. An Objective-C++ implementation can use native frameworks while interfacing with Godot's C++ bindings. If a Swift component or separate native host/helper materially improves the proven focus or capture design, use it and document the reason. Avoid adding several language/runtime boundaries without a demonstrated benefit.

Select and pin compatible versions of Godot, godot-cpp, build tools, Blender, and the importer. Choose the minimum supported macOS version after inspecting the actual test machine and the APIs used. Do not promise broad OS compatibility before testing it.

The native boundary should support:

- Permission state and actionable failure reporting.
- Discovery of eligible application windows.
- Start, update, and stop capture for a source.
- Delivery of frames and their size, scale, content rectangle, and timestamp metadata.
- Input ownership and forwarding for the active target.
- Source lifecycle notifications and cleanup.

Keep the initial bridge small. A simple frame-copy implementation is acceptable for the feasibility prototype if measured and identified as such. Optimize copies or use shared GPU surfaces when performance evidence justifies the complexity. A local source does not inherently require video compression or a streaming server.

### 5.2 Components and responsibilities

| Component | Responsibility |
| --- | --- |
| Window registry | Enumerate eligible windows and expose user-readable app/window labels |
| Source manager | Own capture sessions, metadata, availability, and source lifetimes |
| Native input controller | Acquire/release the active target and forward correctly mapped events |
| Interaction controller | Switch between navigation, console use, assignment, and recovery states |
| Console surface | Display a source and convert surface coordinates into source coordinates |
| Console definition | Stable scene ID, screen geometry, interaction position, and camera pose |
| Assignment store | Persist logical source selectors and support explicit reassignment |
| Ship controller | Movement, collision, doors, spawn, and environmental behavior |
| Diagnostics | Report frame timing, source status, and integration failures |

Treat input as a single-owner state machine. Useful states include navigation, assigning, interacting, and recovering. One transition function should handle releasing the previous target before acquiring the next.

### 5.3 Source identity and persistence

Use stable console IDs independent of imported mesh names. At runtime, track the exact selected native window and its owning application.

Do not persist a native window ID as if it survives an application restart. Store a logical selector, such as application bundle identifier plus user-chosen window matching information. On restart, resolve against current windows. If several candidates match, show a picker instead of routing input to an arbitrary window.

Window titles can change, particularly for browsers, editors, and terminals. Provide a straightforward way to reassign a console. A closed or unavailable source should produce an informative screen state while the ship remains usable.

Persist versioned configuration with sensible defaults and graceful handling of missing or invalid fields. Keep machine-specific paths in local configuration.

### 5.4 Input and coordinates

Implement and verify the complete transformation:

1. Pointer/ray intersection with the console surface.
2. Surface-local normalized coordinates.
3. Captured content coordinates, accounting for letterboxing and cropping.
4. Target window coordinates, accounting for native points, pixels, and scaling.
5. The coordinate system required by the selected native input mechanism.

Clicks outside the displayed content must not reach the target. Do not hardcode a single screen origin, Retina scale, or window size.

Support left/right clicks, double click, press-drag-release, scrolling, key down/up, and modifier combinations. Check both key-based shortcuts and text entry; Unicode typing is not a substitute for shortcut handling. Include an English/Russian text-entry check if those input sources are available on the user's Mac.

Prevent forwarded events from being captured and reinjected recursively. Release held buttons/modifiers on normal exit, target loss, focus loss, and recoverable failures. Keep an independent release path and preserve an ordinary way to leave or quit the app.

Start with a clearly documented release key, such as Right Control, with a configurable alternative. Verify the selected key on the actual keyboard. The release action is consumed locally and never sent to the target.

## 6. Milestones

### M0 — Reproducible project foundation

Tasks:

- [x] Inspect repository, host OS, available tools, and native test access.
- [x] Record actual macOS, hardware, Xcode/command-line tools, and relevant dependency versions.
- [x] Pin a supported Godot/native binding combination and document setup. Godot 4.7 with immutable godot-cpp 4.5-stable API baseline; documented forward compatibility, native runtime validation pending.
- [x] Create a minimal runnable Godot project and a placeholder room with one console. Headless scene/physics assertions pass; GUI acceptance pending.
- [x] Establish build/run scripts and local configuration conventions.
- [x] Add appropriate ignores for generated imports, builds, extracted assets, and local settings.
- [x] Create README.md and a concise progress/validation record.

Historical M0 session acceptance state (2026-11-18): implementation present, acceptance incomplete. `python3 tools/dev.py run` launches the placeholder from the repository root in a local GUI session. Headless physics assertions and an independent Objective-C++/Foundation binary ran on macOS 15.7.7 / M4 Max. The strict automated check is blocked by sandbox user-data errors; fetching native bindings is blocked by shell DNS/network access; GUI launch attempt aborted with exit 134. Full native extension build/load and manual GUI checks remain open. Exact local completion commands and NOT RUN rows are in docs/validation.md. No M1 work performed.

Acceptance:

- A documented command launches the placeholder scene.
- Native and non-native development capabilities are explicitly recorded.
- No milestone is reported Mac-tested before it runs on macOS.

### M1 — One real window, fully interactive

Tasks:

- [x] Implement window discovery/picker and actionable permission setup in source. Backend compiles; source selection verified; permission revocation remains open.
- [x] Capture one selected window and display it on the placeholder console. User verified real Terminal capture on the actual Mac; native build/load also pass.
- [x] Implement navigation/picker/interaction transitions and camera alignment in source. Ray/coordinate and M0 physics assertions pass; normal interaction, release and re-entry verified.
- [x] Implement a target-focus/input prototype: uniquely match AX window, activate/verify target, float Godot, intercept/tag/remap events. SDK backend compiles; the room stayed visible during Terminal use and selected windows respond to clicks.
- [x] Implement coordinate mapping, original Quartz mouse/scroll/key/modifier forwarding, reserved release and watchdog/cleanup in source. Production mapping and ledger/lifecycle checks pass; ordinary clicks, Terminal typing and Obsidian Cmd+C/V verified.
- [ ] Exercise resizing, occlusion, and a minimized source; show clear source state. State/release paths implemented; actual GUI trials NOT RUN.
- [ ] Investigate at least one native menu and one file-dialog workflow early. API boundary/expected failure documented; TextEdit menu and Cmd+O/Cancel trials NOT RUN.
- [x] Record the prototype approach, rejected approaches and evidence limits in docs/architecture.md. Remaining GUI trials are listed below.

M1 state (2026-11-18): **partial, not complete**. Native build/load and the complete automated suite PASS with local CA configuration. The user confirms real Terminal capture, E interaction, `pwd` plus Return with live output, release to navigation, and re-entry without stuck input while the room remains visible. The specific release key used is unspecified; alternate-key and held-input/failure tests remain open. Full editor/browser workflows, drag selection, resize/movement, menus/dialogs, occlusion/minimization and Spaces checks are still outstanding. Agent GUI launch remains unavailable in its execution environment, which does not invalidate the user's successful local GUI run. See docs/validation.md for evidence and scope. Stop at M1; M2 has not started.

Acceptance on the actual Mac:

- Select a real editor window, type a sentence, select text, copy/paste, and use undo.
- Scroll a real browser page and activate a link.
- Click-drag-select and perform a mouse drag without stuck input.
- Operate a real terminal using a harmless command such as pwd.
- Resize/move the source; input continues to land correctly.
- The ship/placeholder environment remains visible while the target is operated.
- Release returns immediately to navigation and leaves no held modifiers/buttons.
- Document behavior of menus, dialogs, minimized windows, and Spaces, including failures.

Gate:

M1 passes only with working end-to-end interaction through Godot. A native-only proof is supporting evidence; the Godot integration must also work. If the focus strategy fails, address it or report the concrete blocker before substantial ship implementation.

### M2 — Two independent consoles and persistent assignments

Tasks:

- [ ] Add a second placeholder console with a different source.
- [ ] Implement shared source management and exclusive input ownership.
- [ ] Add assignment, reassignment, and unavailable-source UI.
- [ ] Save assignments and settings; resolve sources safely after restart.
- [ ] Add basic capture quality controls and per-source scheduling.
- [ ] Stop unused sources and correctly release capture resources.

Acceptance:

- Console A controls one app and console B another; both can display live content.
- Switching consoles moves input ownership without typing into the wrong source.
- Repeat with two distinct windows from the same application; process-only targeting is insufficient.
- Closing and reopening a source does not crash the ship or silently select an ambiguous replacement.
- Restarting the project restores resolvable assignments and offers reassignment for others.
- Leaving a console, disconnecting a source, and quitting clean up captures and input state.

### M3 — KOTOR2 Ebon Hawk asset pipeline

Asset discovery and documentation may proceed earlier, but substantial import/integration follows the native feasibility gate.

Tasks:

- [ ] Locate the user-provided KOTOR2 installation or extracted files; request the path only if discovery cannot resolve it.
- [ ] Identify the actual KOTOR2 interior module, layout, room models, textures, and required dependencies.
- [ ] Pin a compatible Blender/KotORBlender combination and extraction tooling.
- [ ] Create a repeatable extraction/import/export workflow with a written manifest.
- [ ] Assemble rooms using their layout transforms and export to a Godot-compatible format, preferably glTF/GLB.
- [ ] Resolve textures, transparency, normals, lightmaps/emissive materials, scale, and orientation.
- [ ] Create reliable navigation collision; use imported walkmeshes where useful and simpler collision where appropriate.
- [ ] Handle doorways and doors so they do not block required routes.
- [ ] Define a spawn point and recovery/reset position.

Acceptance:

- The original KOTOR2 interior is recognizable and coherently assembled.
- The user can walk through the cockpit, central area, and routes to the intended console rooms.
- Floors and walls have reliable collision; required doorways are traversable.
- Missing textures and import exceptions are listed rather than hidden.
- Another local setup can reproduce the import from the documented user-supplied inputs.

Asset practices:

- Keep extraction inputs, large generated imports, and local installation paths out of normal source commits.
- Keep scripts, import settings, a provenance manifest, and project-authored scene changes in source control.
- Preserve imported base assets and add interaction through separate scene layers or wrappers so reimporting does not erase console behavior.
- Do not hardcode KOTOR1 module names as KOTOR2 facts.
- Do not replace unavailable assets with an unrelated ship and call the environment complete. Keep the placeholder usable while awaiting the correct inputs.

### M4 — Functional consoles throughout the ship

Tasks:

- [ ] Select and document at least three suitable console locations across at least two rooms.
- [ ] Add screen surfaces, interaction bounds, camera poses, and persistent IDs.
- [ ] Integrate the tested source and input system without duplicating native logic per console.
- [ ] Add unobtrusive interaction prompts, active-target labeling, and the release hint.
- [ ] Provide comfortable viewing distance/zoom and maintain source aspect ratio.
- [ ] Add a way to assign/reassign sources without leaving the ship experience.
- [ ] Add display states for unassigned, waiting, paused, and unavailable sources.

Acceptance:

- Three ship consoles can be assigned three distinct real windows.
- The user can walk between them and perform meaningful tasks through each.
- Ordinary editor/browser text is readable at the chosen interaction position.
- Returning to a console preserves the target application's actual state.
- Ship navigation and console mode never consume the same typing/mouse events simultaneously.

### M5 — Native workflow reliability

Tasks:

- [ ] Handle auxiliary windows, menus, sheets, and file dialogs using the simplest proven mechanism compatible with the visible ship.
- [ ] Ensure an auxiliary window associated with the active task can be displayed and operated, or provide a clearly documented explicit in-environment selection flow.
- [ ] Verify source resize/movement, multiple window identities, Spaces, and minimized/restored behavior.
- [ ] Implement permission-denied/revoked recovery, source termination, and stream errors.
- [ ] Verify app focus transitions and release cleanup under failures.
- [ ] Add settings persistence, clear errors, and source reconnection/reassignment.

Acceptance:

- Complete an editor open/save workflow through its native file dialog while the ship remains visible.
- Use representative native menus and browser popup behavior; record app-specific exceptions.
- A lost source produces a recoverable screen and never traps the user in input mode.
- Permission failures explain the action needed and do not produce a crash loop.
- Core scenarios work in a browser, terminal, and editor identified by app and version in the validation record.

Single-window capture may omit separate auxiliary windows. Investigate current APIs and observed app behavior rather than assuming they are included. If a general solution remains incomplete, list exactly which ordinary workflows are blocked and keep this milestone partial.

### M6 — Performance and usability

Initial targets are engineering goals, not measurements already achieved:

| Metric | Initial target / measurement |
| --- | --- |
| Ship rendering | Approximately 60 FPS on the user's M4 Max at a documented resolution and quality preset |
| Active source | Approximately 30 FPS where source content updates that often; prioritize clear text |
| Capture resolution | Start around 1920×1080 output; adjust for source aspect ratio and readability |
| Interaction delay | Aim for under 100 ms end-to-end; record method and measured results or mark unmeasured |
| Inactive sources | Lower resolution/frame rate or pause according to visibility and distance |
| Stability | At least one 30-minute mixed-use session without a crash, stuck input, or progressive resource growth |

Tasks:

- [ ] Measure frame times, capture age, CPU/GPU usage, and memory on the actual Mac.
- [ ] Distinguish capture age from full input-to-visible-response latency.
- [ ] Compare one active source with several visible sources using the same scene and settings.
- [ ] Limit frame queues and discard stale work instead of accumulating latency.
- [ ] Reuse a capture if several consoles reference the same source.
- [ ] Tune scene lighting, materials, source scheduling, and image transfer based on measurements.
- [ ] Add adjustable sensitivity, viewing distance, render quality, capture quality, and ambience volume.
- [ ] Use macOS's normal application audio initially; make ship ambience optional and quiet enough for work.

Acceptance:

- Report actual results with hardware, OS, source applications, source count, and quality settings.
- No placeholder benchmark or unsupported latency claim is presented as measurement.
- A 30-minute session includes walking, editing, browsing, terminal use, source reassignment, and closing/reopening a target.
- If a target is missed, document the practical impact and best working preset.

### M7 — Local application delivery

Tasks:

- [ ] Export a launchable Apple Silicon .app with its native dependencies included.
- [ ] Keep application identity stable across ordinary builds as practical; document signing and permission behavior for local development.
- [ ] Verify permissions from the exported app, not just the Godot editor or development helper.
- [ ] Provide setup, asset preparation, build, run, configuration, and troubleshooting instructions.
- [ ] Document known limitations and the supported app/OS matrix.
- [ ] Validate a fresh launch and an existing-settings launch.
- [ ] Complete the final acceptance checklist and record remaining issues honestly.

Acceptance:

- The user can launch the app without opening the Godot editor.
- Bundled native code loads correctly and permissions apply to the actual delivered application.
- Paths and assets are resolved predictably; missing required assets produce actionable instructions.
- The documented workflow reproduces the local build.

## 7. Verification strategy

Automate tests where they catch real integration or state errors:

- Coordinate transforms: letterboxing, non-unit Retina scaling, source resize, and off-content clicks.
- Source selection: ambiguous matches, changed titles, expired runtime IDs, and missing sources.
- Interaction transitions: target change, lost focus, stream failure, and releasing held input.
- Configuration migration/defaults and invalid configuration recovery.
- Capture scheduling and resource lifecycle where deterministic tests are practical.

Keep automated tests focused. Do not write large collections of tests that merely restate the implementation. Native end-to-end behavior requires actual macOS checks even if mocked tests pass.

Maintain a manual validation matrix including:

| Scenario | Expected outcome |
| --- | --- |
| One console, one editor window | Correct text and shortcuts; visible ship |
| Two consoles, different apps | Correct input ownership after switching |
| Two windows from the same app | Exact selected window receives input |
| Window covered by the ship | Live capture and working interaction |
| Source resized or moved | Correct aspect ratio and input mapping |
| Source minimized then restored | Clear paused state and successful recovery |
| Window on another Space | Recorded display and input behavior; no assumed parity |
| Open/save dialog or popup | Visible, operable task continuation |
| Permission denied or revoked | Actionable message; usable navigation and exit |
| Target closed while dragging/typing | Input released; recoverable source state |
| Assignment restored after restart | Correct match or explicit selection |
| Exported app versus editor | Equivalent core capture/input behavior |

Record each result as PASS, FAIL, BLOCKED, or NOT RUN, with date, environment, and relevant notes. User validation can complete checks unavailable to the agent; never fabricate its outcome.

## 8. Repository and documentation deliverables

Use this as a suggested organization; adapt to the existing repository:

| Path | Purpose |
| --- | --- |
| PLAN.md | This implementation plan and milestone status |
| README.md | Setup, asset preparation, build/run, and normal use |
| project.godot | Godot project |
| scenes/ | Placeholder room, ship, and reusable console scenes |
| scripts/ | Navigation, interaction, assignments, sources, and settings |
| native/ | Native integration source, build configuration, and boundary documentation |
| tools/ | Asset preparation and build/run helpers |
| tests/ | Focused automated checks |
| docs/architecture.md | Proven native integration design and material decisions |
| docs/assets.md | Input requirements, manifest, extraction/import steps, exceptions |
| docs/validation.md | Actual automated/manual results and performance measurements |
| docs/status.md | Completed work, current blocker, next useful step |
| assets/local/ | Ignored user-supplied/extracted assets, if suitable for the chosen pipeline |
| build/ | Ignored generated output |

Keep machine-specific preferences and imported game data local. Prefer useful diagnostic metadata over logging typed text or window contents. Captured frames need not be written to disk for normal operation.

## 9. Final definition of done

- [ ] A locally launchable macOS app presents a navigable KOTOR2 Ebon Hawk interior.
- [ ] At least three consoles across at least two rooms can display distinct real Mac windows.
- [ ] Activating a console enables meaningful mouse/keyboard use of its exact assigned window while the ship remains visible.
- [ ] Two windows from the same app work as separate sources and input targets.
- [ ] A reliable release action returns to navigation without stuck input.
- [ ] Assignment persistence and reassignment handle restarts and missing sources predictably.
- [ ] Ordinary browser, terminal, and editor workflows have documented native test results.
- [ ] Menus and native file dialogs support tested ordinary workflows, with remaining exceptions listed.
- [ ] Source lifecycle and permission failures are recoverable.
- [ ] Performance and a 30-minute mixed-use session have been evaluated on the user's Mac.
- [ ] The exported app and its permission behavior have been tested.
- [ ] Asset preparation, setup, build/run, usage, limitations, and validation are documented.

## 10. References and evidence boundaries

These references informed the plan. Recheck relevant current documentation when implementing, and treat runtime behavior on the target Mac as acceptance evidence.

- [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) — capture setup, window/display filters, app exclusion, metadata, and permissions.
- [Apple: Take ScreenCaptureKit to the next level](https://developer.apple.com/videos/play/wwdc2022/10155/) — single-window behavior, occlusion, Spaces, minimization, auxiliary-window exclusions, and multiple streams. This is historical API guidance; verify behavior and newer options on the chosen deployment target.
- [Apple: CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) — input event construction and posting; not a complete window-control solution.
- [Apple: AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) — Accessibility trust state and prompting.
- [Godot: GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html) — native integration mechanism.
- [Godot: GUI in 3D demo](https://github.com/godotengine/godot-demo-projects/tree/master/viewport/gui_in_3d) — in-world UI interaction pattern, not native desktop control.
- [KotORBlender](https://github.com/seedhartha/kotorblender) — model/layout/walkmesh import and documented compatibility.
- [User's inspiration video](https://www.youtube.com/watch?v=sSqpqQC_TXw&t=79s) — visual reference supplied by the user. Planning used the supplied screenshots and description; the video's implementation was not verified.

## 11. First instruction to the implementing agent

Read this plan, inspect the repository and target environment, and begin M0 followed by M1. The first meaningful success is **one real Mac window operated through one console in the running Godot placeholder scene while the environment remains visible**. Next prove two exact windows, including two from the same app, before scaling the experience into the ship. Update status and validation evidence as work proceeds.
