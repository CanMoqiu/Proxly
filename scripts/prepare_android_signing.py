"""Restore CI signing material without writing secrets to build logs."""
import base64
import os
from pathlib import Path


def property_value(value):
    return (value.replace('\\', '\\\\').replace('\n', '\\n')
            .replace('\r', '\\r').replace('\t', '\\t').replace(' ', '\\ '))


def main():
    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD',
             'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS')
    if any(not os.environ.get(name) for name in names):
        raise SystemExit('Android release signing secrets are not fully configured.')
    os.umask(0o077)
    key = Path(os.environ['RUNNER_TEMP']) / 'proxly-release.p12'
    key.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'], validate=True))
    values = {
        'storeFile': key.as_posix(), 'storeType': 'PKCS12',
        'storePassword': os.environ['ANDROID_KEYSTORE_PASSWORD'],
        'keyPassword': os.environ['ANDROID_KEY_PASSWORD'],
        'keyAlias': os.environ['ANDROID_KEY_ALIAS'],
    }
    Path('android/key.properties').write_text(
        ''.join(f'{name}={property_value(value)}\n' for name, value in values.items()),
        encoding='utf-8')
    print('Android release signing configured.')


if __name__ == '__main__':
    main()
