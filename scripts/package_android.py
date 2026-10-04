"""Verify Android package identity, signing certificate and bundled resources."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile
from package_version import display_version


def signer_fingerprints(output):
    # apksigner labels the v2 signer as "V2 Signer" and newer schemes may use
    # SDK-range labels. Anchor at the APK signer label so source stamps and
    # public-key digests cannot match.
    return {value.lower() for value in re.findall(
        r'^(?:V\d+(?:\.\d+)? Signer|Signer (?:#\d+|\([^\r\n]+\)))' \
        r':? certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$',
        output, re.M)}


def package(build_type):
    if build_type not in ('release', 'debug'):
        raise ValueError('Unknown Android build type')
    root = Path(__file__).resolve().parents[1]
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M).group(1)
    name, number = version.split('+')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    source = root / f'build/app/outputs/flutter-apk/app-{build_type}.apk'
    badging = subprocess.check_output([os.environ['AAPT2'], 'dump', 'badging', str(source)], text=True)
    package_id = 'top.canmoqiu.proxly' + ('.debug' if build_type == 'debug' else '')
    assert f"package: name='{package_id}'" in badging, 'Unexpected Android package ID'
    assert f"versionCode='{number}'" in badging and f"versionName='{name}'" in badging
    if build_type == 'release':
        assert 'application-debuggable' not in badging, 'Release APK must not be debuggable'
    signature = subprocess.check_output([
        os.environ['APKSIGNER'], 'verify', '--verbose', '--print-certs', str(source)
    ], text=True)
    logs = root / 'build-logs'
    logs.mkdir(exist_ok=True)
    (logs / 'apk-signature.txt').write_text(signature, encoding='utf-8')
    (logs / 'apk-badging.txt').write_text(badging, encoding='utf-8')
    fingerprints = signer_fingerprints(signature)
    assert len(fingerprints) == 1, 'Expected one verified signing certificate; see apk-signature.txt'
    fingerprint = fingerprints.pop()
    if build_type == 'release':
        expected = os.environ.get('ANDROID_CERT_SHA256', '').replace(':', '').lower()
        assert re.fullmatch(r'[0-9a-f]{64}', expected), 'Expected release certificate is not configured'
        assert fingerprint == expected, 'Unexpected release signing certificate'
    with zipfile.ZipFile(source) as archive:
        required = [
            'AndroidManifest.xml', 'lib/arm64-v8a/libflutter.so',
            'assets/flutter_assets/assets/web_panel/index.html',
            'assets/flutter_assets/assets/icons/console.svg',
            'assets/flutter_assets/assets/fonts/JetBrainsMono-Regular.ttf',
            'assets/flutter_assets/assets/fonts/ProxlyFlags.woff2',
        ]
        if build_type == 'release':
            required.append('lib/arm64-v8a/libapp.so')
        for entry in required:
            assert entry in archive.namelist(), f'Missing resource: {entry}'
        assert not any(n.endswith(('.p12', '.pfx', '.jks', '.keystore')) for n in archive.namelist())
        assert archive.testzip() is None, 'Corrupt APK archive'
    output = root / 'dist/android'
    output.mkdir(parents=True, exist_ok=True)
    apk = output / f'Proxly-Android-{display_version(name)}.apk'
    shutil.copyfile(source, apk)
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    apk.with_suffix('.apk.sha256').write_text(f'{digest}  {apk.name}\n', encoding='utf-8')
    (output / 'build-info-android.json').write_text(json.dumps({
        'version': version, 'commit': commit, 'package': package_id,
        'build_type': build_type, 'certificate_sha256': fingerprint,
        'file': apk.name, 'sha256': digest,
        'workflow_run': os.environ.get('GITHUB_RUN_ID'),
    }, indent=2) + '\n', encoding='utf-8')
    print(f'Packaged {apk.name}\nSHA-256: {digest}\nCertificate SHA-256: {fingerprint}')


if __name__ == '__main__':
    package(sys.argv[1])
