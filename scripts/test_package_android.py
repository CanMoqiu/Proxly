import unittest
from package_android import signer_fingerprints
from package_version import display_version


class PackageValidationTest(unittest.TestCase):
    def test_numbered_signer(self):
        digest = 'a1' * 32
        self.assertEqual(signer_fingerprints(
            f'Signer #1 certificate SHA-256 digest: {digest}\n'), {digest})

    def test_sdk_range_signers(self):
        digest = 'b2' * 32
        output = (f'Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: {digest}\n'
                  f'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: {digest}\n')
        self.assertEqual(signer_fingerprints(output), {digest})

    def test_v2_signer(self):
        digest = 'd4' * 32
        self.assertEqual(signer_fingerprints(
            f'V2 Signer: certificate DN: CN=Proxly\n'
            f'V2 Signer: certificate SHA-256 digest: {digest}\n'), {digest})

    def test_source_stamp_and_public_key_are_not_app_certificates(self):
        digest = 'c3' * 32
        self.assertEqual(signer_fingerprints(
            f'Source Stamp Signer certificate SHA-256 digest: {digest}\n'
            f'Signer #1 public key SHA-256 digest: {digest}\n'), set())

    def test_distinct_signers_remain_distinct(self):
        output = ''.join(f'Signer #{i} certificate SHA-256 digest: {str(i) * 64}\n'
                         for i in (1, 2))
        self.assertEqual(len(signer_fingerprints(output)), 2)

    def test_package_display_version(self):
        self.assertEqual(display_version('26.6.0+35'), '26.6')
        self.assertEqual(display_version('27.3.4+35'), '27.3.4')


if __name__ == '__main__':
    unittest.main()
