# M0 decisions and toolchain

Recorded 2026-11-18. These choices cover the placeholder foundation only.

| Dependency | Pin / observed version | Reason |
| --- | --- | --- |
| Godot | `4.7.stable.official.5b4e0cb0f`; full commit `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` | Installed standard engine; avoid changing the user's application. Launcher checks exact version. |
| godot-cpp | `godot-4.5-stable`, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` | Immutable released binding baseline; only RefCounted/Object needed now. Uses bundled single-precision 4.5 API. |
| CMake | `4.4.4` | Installed build tool; pin checked by launcher. Avoid adding SCons and another Python package environment. |
| Binding-generator Python | `3.12.15` | Installed mature Python version, chosen instead of the host's much newer default. |
| Default helper Python | `3.15.0` observed | Standard-library helper only; compilation checked with this interpreter. Not used for binding generation. |
| Apple command-line tools | `16.4.0.0.1.1747106510` | Inspected installed package; no automatic global toolchain changes. |
| Apple clang | `17.0.0 (clang-1700.0.13.5)` | Installed compiler; Objective-C++/Foundation compile and execution verified separately. |
| macOS SDK | `15.5` | `xcrun --show-sdk-version`; installed CLT SDK. |
| GNU Make | `3.81` | Installed `/usr/bin/make`; CMake Unix Makefiles generator. |
| Deployment target | `15.0`, arm64 | Conservative local prototype baseline on the inspected 15.7.7 host. Not a tested minimum-OS promise. |
| Blender / importer | Deferred to M3 | No asset pipeline or imported game files in M0. |

Godot documents forward compatibility from an older GDExtension minor API to a newer engine with matching float precision. This supports the selected 4.5 bindings on 4.7; it is **compatibility guidance, not a completed native runtime test**. Sources: [Godot compatibility documentation](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/about_godot_cpp.html#version-compatibility), [binding release](https://github.com/godotengine/godot-cpp/releases/tag/godot-4.5-stable), [immutable binding commit](https://github.com/godotengine/godot-cpp/commit/e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77).

## Small scene foundation

Use GDScript for movement and scene primitives for the room and console. Godot's CharacterBody3D and static box colliders provide ordinary collision without imported assets or extra physics dependencies. GL Compatibility keeps this basic scene simple; M1 can revisit the renderer if measured native texture delivery requires it.

`scenes/placeholder_room.tscn` assembles the reusable player and console scenes. Player origin is at the feet. The spawn marker and initial player transform agree, and the controller records its starting transform for R and fall recovery. No jump keeps the early integration room predictable. Keyboard navigation uses physical WASD keys; pitch is clamped, horizontal diagonal speed is normalized, and focus loss stops navigation until an explicit click resumes.

The console's stable `placeholder_console_01` ID is metadata, independent of future imported mesh names. Its front-facing `Screen` and `ViewPose` marker establish useful geometry for M1 without implementing activation, camera transitions, assignment, or native controls. The screen is static authored content, not a captured window.

## Native boundary

Use one Objective-C++ GDExtension with godot-cpp, rather than a Swift helper, IPC service, or custom Godot build. This keeps native APIs and Godot bindings in one library. M0 registers only `EbonHawkNative : RefCounted` with `build_info()`, which calls Foundation's NSProcessInfo inside an autorelease pool. No capture frameworks, window enumeration, Accessibility queries, event posting, permissions, or focus strategy exist yet.

`native/.gdignore` keeps the optional extension out of automatic editor discovery until explicitly loaded by `tests/native.gd`. The placeholder scene has no native dependency and can run before the native library is built. M1 should deliberately integrate loading and failure reporting after proving this smoke test. The library is non-reloadable; restart Godot after rebuilding. A small godot-cpp build profile includes only the necessary class hierarchy; expand it as M1 adds APIs.

CMake fetches the exact binding commit into ignored build output. It produces one debug dylib. Release builds, universal binaries, signing, app export, capture architecture, and input ownership remain future work. Native source is provided, but its full compilation and Godot loading are blocked by dependency download in this session; see validation.

# M1 prototype — implemented source, native acceptance open

Recorded 2026-11-18. The M0 description above is historical. M1 now explicitly loads the optional extension from the room's ConsoleController; `native/.gdignore` continues to prevent editor auto-loading and missing-library errors. The standard GDExtension pin is unchanged. **This design is not yet a proven native integration**: backend compile/link succeeds, but GitHub DNS prevents building the Godot bridge and the GUI process aborts in this execution environment.

## Boundary and capture

`session.mm` owns the macOS APIs independently of Godot; `bridge.mm` converts Foundation values to Godot Variants on the main thread. This permits compilation of the complete platform backend even when godot-cpp cannot be downloaded. An ARC Objective-C++ session owns the stream, AX references, event tap, and input ledger. There is no Swift host, network transport, or app-specific scripting bridge.

SCShareableContent supplies window IDs and owning application/title labels, excluding this process, tiny windows and nonzero window layers. Discovery includes off-screen sources rather than equating `onScreen == false` with minimization. The permission UI separately reports capture, Accessibility, and listen-event access and requests grants only on an explicit button press.

Capture uses a desktop-independent single-window SCContentFilter, BGRA8, no audio/cursor/shadow, and a requested 30 FPS / maximum 1920-pixel edge. Source display scale comes from the filter rather than a hardcoded Retina factor. A serial capture queue reads complete CMSampleBuffers, honors row stride, converts BGRA to tightly packed RGBA, and replaces a single latest-frame slot. Idle frames keep availability fresh; blank/suspended/stopped/error states disable interaction. Godot creates/updates one ImageTexture and applies it to the existing 3D screen through an aspect-fit shader. This deliberately uses CPU copies; frame-copy cost, latency, and FPS are unmeasured. Captured frames and typed input are never written to disk.

Reference: [Apple's capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) describes stream configuration, output callbacks and metadata. Installed SDK 15.5 headers were also inspected and used for compile validation.

## Focus/window strategy to test

1. Match the selected SCWindow to exactly one AX window in its owning PID using current global point bounds and, when supplied, title. Reject zero/multiple candidates. This is a public-API identity **inference**, not an authoritative CGWindowID→AX mapping; app-specific identity behavior remains to be tested.
2. Save the Godot NSWindow's level/hide/Space settings. Temporarily use floating level, stay visible on deactivation, and allow all Spaces/fullscreen auxiliary placement. Activate the target application, raise the matched AX window, request main/focused-window status. Godot remains rendered; no target screenshot overlay substitutes for the room.
3. Before every forwarded event, verify target PID is frontmost, `AXFocusedWindow` equals the retained AX element, it is not minimized, its bounds still match the selected capture window, and capture geometry agrees. A changed/modal/ambiguous window releases input. Activation has a short settling period, but events are never sent before the focus checks pass.
4. Copy original physical Quartz events and post to the target PID. Mouse location is remapped; the two public window-under-pointer fields are changed from the original Godot window ID to the selected capture window ID. **These fields and CGEventPostToPid do not establish a universal exact-window routing guarantee.** Verification with the actual apps is the feasibility gate.
5. On release restore the saved Godot window settings, activate Godot, restore the navigation camera, and require a click before walking. Godot's local navigation actions are released when navigation stops, because native interception can consume key-up events.

Public API basis: [NSWindow levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct), [AX focused-window attribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute), [AX raise action](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/actions), [CGEvent APIs](https://developer.apple.com/documentation/coregraphics/cgevent). Raising or PID posting alone was rejected as sufficient evidence of correct targeting. Keeping Godot key/frontmost and blindly injecting background events was rejected because it does not solve target keyboard focus. Hiding Godot or presenting the real app above it does not satisfy the requested experience and is not used as a successful interaction mode.

## Coordinate pipeline

The native tap reports Quartz desktop pointer coordinates converted through the actual Godot NSWindow/content view into logical view coordinates, with Cocoa/Quartz Y inversion relative to the main display. Godot scales these to its actual viewport size and intersects the camera ray with the console screen plane. Screen-local coordinates yield top-left UVs; a shared aspect-fit rectangle rejects bars and off-surface points.

The SDK defines `SCStreamFrameInfoContentRect` in points in the output surface. Multiply it by the reported scale factor **once** to obtain the pixel crop. The shader samples only that crop. Input converts the accepted UV into a crop pixel, then uses `(pixel - crop.origin) / crop.size` to map to the latest AX/SCWindow rectangle in native desktop points. This ratio cancels Retina and capture downscale; it does not assume a screen origin or native window size. Content scale additionally verifies original captured dimensions against the AX frame, refusing events on stale/mismatched geometry. No sourceRect crop is configured. These metadata assumptions are SDK-based and require real Retina/resize tests.

`console_mapping.gd` contains the production transform functions tested with margins, bars, negative display origins, resize, move, downscale, and an actual scene camera ray. The shader uses the same fitted rectangle supplied by the controller. Invalid points never forward pointer downs/motion; an up for an already-forwarded button can still release at the last valid target point when the pointer leaves the screen.

## Input ownership and recovery

The controller has navigation, picker, and interaction states. Only the interaction state polls and forwards native event tokens. A session event tap runs on its own CFRunLoop thread and suppresses intercepted physical events, preventing an additional native click from activating the Godot window or reaching an unrelated window. Event copies retain click counts, drag type, scroll fields, raw keycodes, Unicode payload if present, and modifier flags. They are tagged to bypass reinjection into the tap. No Unicode-only text emulation replaces keyboard shortcuts; English/Russian input still needs actual testing.

Right Control (macOS keycode 62) or optional F12 (111), plus Escape, are consumed locally. Cmd+Q requests Godot quit; Cmd+Tab releases and allows ordinary app switching. A native 250 ms watchdog releases input if Godot stops polling for 1.5 seconds, the tap is disabled, or its bounded queue overflows. The release path does not wait for the Godot frame loop to drain held events. The tap passes through once inactive; main-thread polling restores window/camera state. OS process termination remains the ordinary last-resort exit if a process cannot recover.

A mutex-protected ledger tracks forwarded keys/buttons and modifier snapshots. Release drains it once, synthesizes key/modifier/button ups to the target PID, and discards queued/pending events. The same path covers normal exit, reassign, capture failure, target focus/geometry loss, minimization, timeout, and stop. Repeated release is idempotent. No unpaired pointer-up or key-up is forwarded. Delivery of synthesized ups to actual applications is still unverified; the automated ledger/lifecycle checks do not establish OS delivery.

## Menus, dialogs, occlusion, and Spaces

Only one primary window is captured. No claim is made that native menus, separate popup windows, open/save panels, or sheets are included. The current strategy can continue only while the retained AX window remains focused; otherwise it releases with a reason. A menu remaining in the same AX window may still be visually missing from the capture. An Open panel becoming a separate focused AX window is expected to trigger release. These are **predictions from the API boundaries, not observed app results**. No menu/file-dialog GUI workflow could be performed here; the validation matrix keeps them NOT RUN.

The floating/all-Spaces policy is intended to preserve Godot visibility when activation changes Space. Fullscreen, Stage Manager, multiple displays, occlusion, minimized capture, and Space transitions remain unverified. AX minimization is used when the source can be matched; otherwise an absent source is conservatively reported unavailable instead of guessing that it closed. Refresh/resize/input errors retain a usable room and a source state. Manual restoration/reassignment is explicit. Do not call M1 passed until the real-editor/browser/terminal matrix is completed with the room visible.
