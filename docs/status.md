# Status — 2026-11-18

M1 prototype source is implemented in the M0 placeholder. **Terminal capture, typing, Obsidian clipboard shortcuts, and ordinary clicks in selected windows are user-verified on the actual Mac; M1 acceptance remains incomplete.** M2 has not started.

Current automated results:

- Full native extension build: PASS, exit 0, no compiler warnings in the final build. The binding profile includes OS for godot-cpp logging, and dependency headers are treated as system headers while project warnings remain enabled.
- Godot native smoke: PASS, exit 0; class registration, initial state/permissions, no-source refusal, repeated cleanup, and Objective-C++ call.
- Full `tools/dev.py check`: PASS, exit 0; script parsing, M0 physics, coordinate/ray assertions, and headless scene startup.
- Standalone macOS backend compile/link/lifecycle/input-ledger checks: PASS.

The certificate startup error was resolved locally using ignored override.cfg with `/etc/ssl/cert.pem`. A reproducible example is in config/macos-ca.example.cfg. TLS verification and strict error detection remain enabled. Dependency download/build and certificate errors are no longer blockers in this workspace.

User GUI results (2026-11-18): PASS for selecting/displaying the real Terminal on the console, E interaction, typing `pwd` and Return with live output, releasing with Right Control or Escape and resuming WASD after clicking Godot, and re-entering without stuck keys/modifiers. The user confirmed all three requested checks. The specific release key used was not identified; F12 and held-button/failure-path cleanup remain untested. This establishes the Terminal path with the room visible, not the whole app matrix.

Agent GUI execution limitation: a fresh GUI smoke launch still aborts with exit 134 in this execution environment. An existing crash report points to AppKit/LaunchServices application registration (`_RegisterApplication`, `NSApplication init`), before scene execution. No connected GUI inspection/control tool is available. The user can run the GUI and has confirmed actual Terminal capture/input. Editor and browser workflows, mouse drag/double-click/scroll, resize/movement, menus/dialogs, occlusion, minimization, Spaces and failure-path cleanup remain open. Earlier standalone permission preflights apply only to that test executable; the user successfully enabled capture for the running Godot application.

See [validation.md](validation.md) for current results and the open manual matrix. Preserve M0 behavior; keep M1 open until the real-window workflows pass with the 3D room visible.
