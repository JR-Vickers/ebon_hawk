#!/usr/bin/env python3
"""Small, dependency-free development entry point. Run from any directory."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE = "4.7.stable.official.5b4e0cb0f"
CMAKE = "4.4.4"


def run(args, *, godot=False, godot_timeout=60):
    try:
        result = subprocess.run([str(x) for x in args], cwd=ROOT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=godot_timeout if godot else None)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        print(output.decode(errors="replace") if isinstance(output, bytes) else output, end="")
        raise SystemExit(f"Godot check timed out after {godot_timeout} seconds; inspect script/runtime errors above.")
    print(result.stdout, end="", flush=True)
    # Godot can exit zero after a script/resource error.
    if result.returncode or (godot and ("ERROR:" in result.stdout or "SCRIPT ERROR:" in result.stdout)):
        raise SystemExit(result.returncode or 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["run", "run-ship", "reload-ship", "ship-check", "reload-check", "reload-validate", "editor", "check", "native", "native-check", "platform-check", "mouse-fixture"])
    args = parser.parse_args()
    if args.command == "reload-ship":
        try:
            endpoint = json.loads((ROOT / "build/ship-reload.json").read_text())
            if time.time() - endpoint["heartbeat"] > 5:
                raise OSError("ship preview heartbeat expired")
            request = ROOT / "build" / f"ship-reload-request-{endpoint['pid']}"
            temporary = request.with_name(request.name + "." + uuid.uuid4().hex)
            temporary.write_text("reload\n")
            os.replace(temporary, request)
        except (OSError, KeyError, ValueError, TypeError) as error:
            raise SystemExit(f"No running ship preview accepts reload requests: {error}")
        print("Ship reload requested; it will run when the preview is idle.")
        return
    config_path = ROOT / "config/local.json"
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    engine = os.environ.get("GODOT") or config.get("godot") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
    version = subprocess.check_output([engine, "--version"], text=True).strip()
    if version != ENGINE:
        raise SystemExit(f"Expected Godot {ENGINE}, found {version}. Set GODOT or config/local.json.")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    (build / ".gdignore").touch()
    base = [engine, "--path", ROOT, "--log-file", build / "godot.log"]
    if args.command in ("run", "run-ship", "editor"):
        os.execv(engine, [str(x) for x in base + (["--editor"] if args.command == "editor" else ["--fullscreen", "res://scenes/ship_reload_host.tscn"] if args.command == "run-ship" else [])])
    elif args.command == "check":
        for script in ["scripts/player.gd", "scripts/console_mapping.gd", "scripts/console_controller.gd", "scripts/source_selector.gd", "tests/source_selector.gd", "tests/foundation.gd", "tests/console_mapping.gd", "tests/native.gd"]:
            run(base + ["--headless", "--check-only", "--script", script], godot=True)
        run(base + ["--headless", "--fixed-fps", "60", "--script", "tests/foundation.gd"], godot=True)
        run(base + ["--headless", "--script", "tests/console_mapping.gd"], godot=True)
        run(base + ["--headless", "--script", "tests/source_selector.gd"], godot=True)
        run(base + ["--headless", "--script", "tests/window_picker.gd"], godot=True)
        run(base + ["--headless", "--quit-after", "120"], godot=True)
    elif args.command == "ship-check":
        if any(not (ROOT / "assets/generated/ship" / name).exists() for name in
               ("ebon_hawk.glb", "collision.glb", "furniture_collision.glb")):
            raise SystemExit("Generate ship assets first; see docs/assets.md.")
        run(base + ["--headless", "--script", "tests/ship.gd"], godot=True, godot_timeout=15)
        if (ROOT / "assets/generated/ship_audio/manifest.json").exists():
            run(base + ["--headless", "--script", "tests/ship_audio.gd"], godot=True, godot_timeout=15)
    elif args.command == "reload-check":
        run(base + ["--headless", "--script", "tests/ship_reload.gd"], godot=True)
    elif args.command == "reload-validate":
        base = [engine, "--path", ROOT, "--log-file", build / "ship-reload-godot.log"]
        for script in sorted((ROOT / "scripts").rglob("*.gd")):
            run(base + ["--headless", "--check-only", "--script", script], godot=True, godot_timeout=15)
        run(base + ["--headless", "--script", "tests/ship.gd"], godot=True, godot_timeout=15)
    elif args.command == "native":
        cmake = config.get("cmake") or shutil.which("cmake")
        if not cmake:
            raise SystemExit(f"Install CMake {CMAKE} first.")
        found = subprocess.check_output([cmake, "--version"], text=True).splitlines()[0]
        if found != f"cmake version {CMAKE}":
            raise SystemExit(f"Expected CMake {CMAKE}; found {found}")
        python = config.get("python") or shutil.which("python3.12")
        if not python or subprocess.check_output([python, "--version"], text=True).strip() != "Python 3.12.15":
            raise SystemExit("Native binding generation requires Python 3.12.15; set python in config/local.json.")
        run([cmake, "-S", ROOT / "native", "-B", build / "native", "-G", "Unix Makefiles",
             "-DCMAKE_BUILD_TYPE=Debug", "-DCMAKE_OSX_ARCHITECTURES=arm64",
             "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0", f"-DPython3_EXECUTABLE={python}"])
        run([cmake, "--build", build / "native", "--parallel", "8"])
    elif args.command == "mouse-fixture":
        run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-arch", "arm64", "-mmacosx-version-min=15.0",
             "-Wall", "-Wextra", "-Werror", "tests/mouse_fixture.mm", "-framework", "Foundation",
             "-framework", "AppKit", "-o", build / "mouse_fixture"])
    elif args.command == "platform-check":
        run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-arch", "arm64", "-mmacosx-version-min=15.0",
             "-Wall", "-Wextra", "-Werror", "native/src/session.mm", "tests/platform.mm",
             "-framework", "Foundation", "-framework", "AppKit", "-framework", "ApplicationServices",
             "-framework", "ScreenCaptureKit", "-framework", "CoreMedia", "-framework", "CoreVideo",
             "-o", build / "platform_checks"])
        run([build / "platform_checks"])
    else:
        library = ROOT / "native/bin/libebon_hawk.dylib"
        if not library.exists():
            raise SystemExit("Run python3 tools/dev.py native first.")
        run(base + ["--headless", "--script", "tests/native.gd"], godot=True)


if __name__ == "__main__":
    main()
