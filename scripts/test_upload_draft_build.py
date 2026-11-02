import unittest
from upload_draft_build import validate_destination


class DraftDestinationTest(unittest.TestCase):
    def setUp(self):
        self.commit = 'a' * 40
        self.release = dict(tagName='v26.8.1', isDraft=True,
                            isPrerelease=True, targetCommitish=self.commit)

    def test_matching_private_beta_draft_is_allowed(self):
        validate_destination({'private': True}, self.release,
                             'v26.8.1', self.commit, '26.8.1')

    def test_public_repository_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_destination({'private': False}, self.release,
                                 'v26.8.1', self.commit, '26.8.1')

    def test_published_wrong_tag_or_wrong_commit_are_rejected(self):
        for field, value in [('isDraft', False), ('isPrerelease', False),
                             ('tagName', 'v26.8.2'), ('targetCommitish', 'main')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_destination({'private': True}, {**self.release, field: value},
                                     'v26.8.1', self.commit, '26.8.1')

    def test_formal_and_mismatched_versions_are_rejected(self):
        for version in ['26.8.0', '26.8.2', '../26.8.1']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate_destination({'private': True}, self.release,
                                     'v26.8.1', self.commit, version)


if __name__ == '__main__':
    unittest.main()
