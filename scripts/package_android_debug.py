"""Package the CI-signed debug APK for personal regression testing."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile
from package_version import display_version


def main():
    root = Path(__file__).resolve().parents[1]
    version = re.search(r"^version:\s*(\S+)", (root / "pubspec.yaml").read_text(), re.M).group(1)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    source = root / "build/app/outputs/flutter-apk/app-debug.apk"
    with zipfile.ZipFile(source) as archive:
        names = set(archive.namelist())
        for entry in (
            "AndroidManifest.xml",
            "lib/arm64-v8a/libflutter.so",
            "assets/flutter_assets/assets/web_panel/index.html",
        ):
            if entry not in names:
                raise RuntimeError(f"Missing APK entry: {entry}")
        if archive.testzip() is not None:
            raise RuntimeError("APK ZIP integrity check failed")
    output = root / "dist/android"
    output.mkdir(parents=True, exist_ok=True)
    apk = output / f"Proxly-Android-{display_version(version)}.apk"
    shutil.copyfile(source, apk)
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    apk.with_suffix(".apk.sha256").write_text(f"{digest}  {apk.name}\n", encoding="utf-8")
    (output / "build-info.json").write_text(json.dumps({
        "version": version,
        "commit": commit,
        "package": "top.canmoqiu.proxly.debug",
        "build_type": "debug",
        "signing": "CI Android debug key; separate installation from the release app",
        "file": apk.name,
        "sha256": digest,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Packaged {apk.name}\nSHA-256: {digest}")


if __name__ == "__main__":
    main()
