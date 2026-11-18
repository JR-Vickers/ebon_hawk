# Status — 2026-11-18

M1 prototype source is implemented in the M0 placeholder. **M1 is not accepted: no real application window has been operated through Godot in this session.** M2 has not started. Working M0 navigation/physics remains available without the native library.

Implemented source:

- ScreenCaptureKit window discovery, application/title picker, permission preflight and explicit request UI.
- Single-window capture, latest-frame RGBA handoff and live-console texture path, aspect-fit coordinate mapping, native point/Retina metadata handling.
- Camera alignment and navigation/picker/interaction ownership; target/release hints.
- AX window matching/focus checks, floating Godot window, native input tap, original mouse/key/scroll forwarding, reserved Right Control/F12/Escape, reinjection tags and watchdog.
- Forwarded-input cleanup and source/focus/resize/minimize/error states. Menus/dialogs remain an unverified single-window limitation.

Verified: the complete standalone macOS backend compiles and links with `-Wall -Wextra -Werror`; session lifecycle and input-ledger assertions pass. Godot script parsing, coordinate/ray assertions and existing M0 physics assertions pass. The strict combined check remains blocked by Godot's system-certificate startup error.

Remaining blockers:

- Shell cannot resolve github.com, so pinned godot-cpp cannot be fetched. The Godot bridge has not compiled/loaded; no native texture or input path has been exercised inside Godot.
- A new non-headless Godot smoke launch aborts with exit 134. No connected GUI inspection/control tool is available. No actual click/type/drag, app-focus, menu/dialog, minimization, occlusion or Spaces result can be claimed.
- The separate backend test process reports capture/Accessibility/Input Monitoring denied. This is **that executable's** preflight, not proof of Godot's permission state. Godot must request/check its own grants after building.

Next: run the exact build/launch commands and local permission/GUI matrix in [validation.md](validation.md). Keep M1 open until actual end-to-end results demonstrate correct-window input with the 3D room visible. The focus strategy remains a prototype; a successful API call alone does not pass the gate.
