"""Deliver verified beta packages to an existing private draft without publishing it."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def validate_destination(repository, release, tag, commit, version):
    if repository.get('private') is not True:
        raise ValueError('Draft delivery is restricted to private repositories')
    if not re.fullmatch(r'\d+\.\d+\.[1-9]\d*', version) or tag != f'v{version}':
        raise ValueError('Draft tag must match the current beta version')
    if release.get('tagName') != tag or release.get('isDraft') is not True:
        raise ValueError('The matching release must already exist as a draft')
    if release.get('isPrerelease') is not True:
        raise ValueError('Beta delivery requires a prerelease draft')
    if release.get('targetCommitish') != commit:
        raise ValueError('Draft target must be the full checked-out commit SHA')


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main(platform):
    if platform not in ('verify', 'android', 'ios'):
        raise ValueError('Unsupported delivery mode')
    root = Path(__file__).resolve().parents[1]
    version = re.search(r'^version:\s*(\S+)',
                        (root / 'pubspec.yaml').read_text(), re.M).group(1).split('+')[0]
    repository = os.environ['GITHUB_REPOSITORY']
    tag = os.environ['DRAFT_RELEASE_TAG']
    if not re.fullmatch(r'\d+\.\d+\.[1-9]\d*', version) or tag != f'v{version}':
        raise ValueError('Draft tag must match the current beta version')
    commit = output('git', 'rev-parse', 'HEAD')
    metadata = json.loads(output('gh', 'api', f'repos/{repository}'))
    release = json.loads(output('gh', 'release', 'view', tag, '--repo', repository,
                                '--json', 'tagName,isDraft,isPrerelease,targetCommitish'))
    validate_destination(metadata, release, tag, commit, version)
    if platform == 'verify':
        print('Verified private beta draft and source commit')
        return
    system, extension = ('Android', 'apk') if platform == 'android' else ('iOS', 'ipa')
    package = root / 'dist' / platform / f'Proxly-{system}-{version}.{extension}'
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    manifest = package.with_suffix(f'.{extension}.sha256').read_text().split()
    if manifest != [digest, package.name]:
        raise ValueError('Package checksum does not match its build manifest')
    build = json.loads((package.parent / f'build-info-{platform}.json').read_text())
    if build['commit'] != commit:
        raise ValueError('Package was built from a different commit')
    # Do not clobber existing assets or publish the draft during build retries.
    subprocess.run(['gh', 'release', 'upload', tag, str(package), '--repo', repository], check=True)
    print(f'{package.name}\nSHA-256: {digest}')


if __name__ == '__main__':
    main(sys.argv[1])
