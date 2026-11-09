"""Check supported devices without building or packaging an application."""
import copy
import unittest

from package_ios import validate_device_support


class DeviceSupportTest(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": "top.canmoqiu.proxly",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "MinimumOSVersion": "18.0",
            "UIDeviceFamily": [1, 2],
            "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
            ],
            "NSLocalNetworkUsageDescription": "Local controller access",
            "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
        }

    def test_universal_device_build_is_accepted(self):
        validate_device_support(self.info)

    def test_phone_only_build_is_rejected(self):
        self.info["UIDeviceFamily"] = [1]
        with self.assertRaises(AssertionError):
            validate_device_support(self.info)

    def test_missing_tablet_orientation_is_rejected(self):
        for orientation in self.info["UISupportedInterfaceOrientations~ipad"]:
            info = copy.deepcopy(self.info)
            info["UISupportedInterfaceOrientations~ipad"].remove(orientation)
            with self.subTest(orientation=orientation), self.assertRaises(AssertionError):
                validate_device_support(info)

    def test_phone_landscape_is_rejected(self):
        self.info["UISupportedInterfaceOrientations"].append("UIInterfaceOrientationLandscapeLeft")
        with self.assertRaises(AssertionError):
            validate_device_support(self.info)


if __name__ == "__main__":
    unittest.main()
