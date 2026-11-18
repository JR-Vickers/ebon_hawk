# Ebon Hawk Desktop

A Godot placeholder room with first-person movement and one console. M1 capture/input prototype source is implemented, with **user-verified Terminal capture, `pwd` execution, release to navigation, clean re-entry, and working clicks in selected application windows**. The full native extension builds and its Godot smoke check passes. Automated checks pass with the documented local CA-bundle override; the remaining GUI acceptance matrix stays open. See [validation](docs/validation.md). M2 has not started.

## Launch

From this directory:

```sh
python3 tools/dev.py run
```

The launcher uses `/Applications/Godot.app/Contents/MacOS/Godot` by default and requires **Godot 4.7 stable**, official build `5b4e0cb0f` (standard, single precision, no .NET requirement). Install the matching release from the [official archive](https://godotengine.org/download/archive/4.7-stable/) if needed. The installed engine was inspected on this Mac; the repository does not download or replace it.

WASD moves; mouse looks. Escape releases the pointer and stops movement; left-click resumes. R resets position and view. Focus loss releases the pointer and stops movement; click to resume after returning. Cmd+Q or closing the window quits. There is no jump. Without a built native library the M0 room still runs.

For the M1 prototype, first open an ordinary TextEdit, browser, or Terminal window. Build the native extension, then launch with `python3 tools/dev.py run` (use a standalone game window, not embedded editor play). Walk toward the console, press **P** for the window picker and permission status, then choose a window by application/title/ID. The console should display it after capture starts. Press **E** near the console to align the camera and acquire input.

During interaction, the target application becomes active behind the floating Godot window. **Right Control or Escape** releases control; the picker offers **F12** as an alternative (possibly Fn+F12). **Cmd+Q quits Godot**, and Cmd+Tab releases before switching apps. Other typing and mapped pointer events go to the selected source. Click in Godot after release to resume navigation. The visible hint names the active target and reserved key. Input is refused on ambiguous Accessibility matches or changed focus/geometry; re-enter with E only after the source is live again.

Under **System Settings → Privacy & Security**, enable **Screen & System Audio Recording** (called Screen Recording on some macOS versions), **Accessibility**, and **Input Monitoring** for the running **Godot** application. The picker has an explicit Request permissions button. Restart Godot after grants and refresh the picker. These permissions belong to the host app, not the dylib or this repository. Do not grant only the standalone `platform_checks` test executable and expect Godot to inherit the grants.

The pointer's local cross is the input location on the console; letterbox/pillarbox clicks are discarded. Only the selected primary window is captured. A separate native menu/popup or file dialog may be absent; a focused-window change releases input instead of silently controlling a different window. Menu/dialog, Spaces, occlusion, and real input behavior are **unverified**. The source state and release reason are shown on screen. Restore minimized sources in macOS, wait for capture to resume, then press E. Reassign closed/unavailable sources with P.

The player starts at `(0, 0.05, 3)`, looking down negative Z at console 01 at `(0, 0, -3)`. The room is 12 × 12 meters with four solid walls. Camera height is 1.65 meters. Adjust `speed` and `mouse_sensitivity` on the Player instance in the inspector.

## Development commands

```sh
python3 tools/dev.py editor       # Open the Godot editor
python3 tools/dev.py check        # Parse scripts, physics assertions, main-scene smoke
python3 tools/dev.py native       # Fetch pinned godot-cpp, build arm64 debug dylib
python3 tools/dev.py native-check # Load extension; inspect initial state and refusal without a source
python3 tools/dev.py platform-check # Compile/link backend, lifecycle and input-ledger checks; no godot-cpp
```

The placeholder runs without the native build. `check` fails on nonzero process status **or any Godot ERROR**, including environmental startup errors; inspect the printed output rather than assuming an exit code of zero from Godot means success.

Native prerequisites: Apple command-line tools (`xcode-select --install` if absent), macOS SDK, Git, **CMake 4.4.4**, and **Python 3.12.15** for binding generation. The native build uses Unix Makefiles, C++17/Objective-C++17, arm64, and deployment target macOS 15.0. Only macOS 15.7.7 has been inspected; broader support is untested. No full Xcode installation is required by this build recipe. See [architecture and version decisions](docs/architecture.md) for exact pins and compatibility evidence.

First native build needs access to `github.com`; later builds reuse `build/native/`. Output is `native/bin/libebon_hawk.dylib`. `native-check` should print native OS/build information and `Native load and Objective-C++ call: PASS`. This is only a build/load/lifecycle check, not desktop integration. The requested capture limit is 30 FPS and a 1920-pixel maximum edge; performance has not been measured. Exports, signing, and bundling into an `.app` belong to M7.

## Local configuration

Defaults work with the inspected installation. To use other installation paths:

```sh
cp config/local.example.json config/local.json
```

Edit the `godot`, `cmake`, and `python` executable paths. `GODOT` overrides the configured engine path. Exact engine, CMake, and binding-generator Python versions are checked by the launcher. `python3` used to launch the helper can be newer; it uses only the standard library. Local JSON is developer tooling configuration, not an in-game settings store. Invalid JSON fails visibly.

If Godot reports `get_system_ca_certificates` / `ret != noErr`, this session resolved it by setting a local CA bundle in ignored `override.cfg`. Merge [config/macos-ca.example.cfg](config/macos-ca.example.cfg) into that file, preserving other overrides. This uses macOS's `/etc/ssl/cert.pem` instead of querying Keychain anchors; TLS verification stays enabled. It does not include user-installed Keychain trust overrides. The local override is already configured in this workspace; no action is needed here. The strict checks continue to reject all ERROR lines.

Keep shared Godot settings in `project.godot` and authored scenes in `scenes/`. Optional Godot `override.cfg` is local and ignored. Future persistent application settings should use versioned `user://` files (normally `~/Library/Application Support/Godot/app_userdata/Ebon Hawk Desktop/` on this Mac); M0 does not implement a settings or assignment store. Logs from helpers are directed into ignored `build/`.

`.godot/`, `build/`, native binaries, local configuration, and `assets/local/`, `assets/extracted/`, `assets/generated/` are ignored. Keep user-supplied game files and installation paths there when the asset milestone begins. Authored `.uid` files are retained. No extracted assets, Blender, importer, or export templates are needed for M0.

See [status](docs/status.md), [validation and local acceptance checks](docs/validation.md), and [architecture](docs/architecture.md).
