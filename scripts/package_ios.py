"""Validate a device Release build and package an unsigned, re-signable IPA."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile
from package_version import display_version


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def package(app: Path, output: Path) -> Path:
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    assert info["CFBundleIdentifier"] == "top.canmoqiu.proxly", "Unexpected bundle ID"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not a device build"
    assert info["MinimumOSVersion"] == "18.0", "Unexpected deployment target"
    assert info["UIDeviceFamily"] == [1], "Expected an iPhone target"
    assert info["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
    assert info.get("NSLocalNetworkUsageDescription"), "Missing local network purpose"
    assert info["NSAppTransportSecurity"]["NSAllowsLocalNetworking"] is True

    required = [
        app / info["CFBundleExecutable"],
        app / "Frameworks/Flutter.framework/Flutter",
        app / "Frameworks/App.framework/App",
        app / "Frameworks/App.framework/flutter_assets/assets/web_panel/index.html",
        app / "Frameworks/App.framework/flutter_assets/assets/fonts/JetBrainsMono-Regular.ttf",
        app / "Frameworks/App.framework/flutter_assets/assets/fonts/ProxlyFlags.woff2",
        app / "Frameworks/App.framework/flutter_assets/assets/app_icon.png",
        app / "Frameworks/App.framework/flutter_assets/assets/icons/console.svg",
        app / "en.lproj/InfoPlist.strings",
        app / "zh-Hans.lproj/InfoPlist.strings",
    ]
    for path in required:
        assert path.is_file(), f"Missing resource: {path}"
    for binary in required[:3]:
        arch = run("lipo", "-archs", str(binary)).split()
        assert "arm64" in arch and "x86_64" not in arch, f"Invalid device architecture: {arch}"
    # Development profiles and personal signing material must not be embedded.
    assert not (app / "embedded.mobileprovision").exists(), "Unexpected signing profile"
    assert not list(app.rglob("*.p12")), "Unexpected signing certificate"

    sha = run("git", "rev-parse", "HEAD")
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    assert re.fullmatch(r"[0-9.]+", version)
    assert re.fullmatch(r"[0-9.]+", build)
    output.mkdir(parents=True, exist_ok=True)
    ipa = output / f"Proxly-iOS-{display_version(version)}.ipa"
    # ditto preserves framework symlinks and executable permissions on macOS.
    payload = output / "Payload"
    payload.mkdir(exist_ok=True)
    subprocess.run(["ditto", str(app), str(payload / "Runner.app")], check=True)
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(payload), str(ipa)], check=True)
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None, "Corrupt IPA archive"
        assert "Payload/Runner.app/Info.plist" in archive.namelist()
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    ipa.with_suffix(".ipa.sha256").write_text(f"{digest}  {ipa.name}\n", encoding="utf-8")
    metadata = {
        "commit": sha, "version": version, "build": build,
        "bundle_id": info["CFBundleIdentifier"], "minimum_ios": info["MinimumOSVersion"],
        "signed": False, "sha256": digest,
        "flutter": run("flutter", "--version"), "xcode": run("xcodebuild", "-version"),
        "workflow_run": os.environ.get("GITHUB_RUN_ID"),
    }
    (output / "build-info-ios.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    # Only deliver the archive and manifest, not a duplicate expanded application.
    import shutil
    shutil.rmtree(payload)
    print(ipa)
    return ipa


if __name__ == "__main__":
    package(Path("build/ios/iphoneos/Runner.app"), Path("dist/ios"))
