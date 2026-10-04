"""Shared user-facing version format for mobile artifact names."""
import re


def display_version(raw):
    version = raw.split('+')[0]
    match = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)', version)
    if not match:
        raise ValueError(f'Expected a three-part app version: {version}')
    year, release, test = match.groups()
    return f'{year}.{release}' if test == '0' else version
