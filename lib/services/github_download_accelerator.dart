class GitHubDownloadAccelerator {
  GitHubDownloadAccelerator._();

  static const List<String> _proxyPrefixes = [
    'https://gh.llkk.cc/',
    'https://gh.ddlc.top/',
    'https://ghfast.top/',
  ];

  static List<String> candidates(String url, {bool includeMirrors = true}) {
    final uri = Uri.tryParse(url);
    if (!includeMirrors || uri == null || !_isGitHubReleaseDownload(uri)) {
      return [url];
    }

    final urls = <String>[
      for (final prefix in _proxyPrefixes) '$prefix$url',
      url,
    ];
    return urls.toSet().toList(growable: false);
  }

  static bool _isGitHubReleaseDownload(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.pathSegments.length >= 5 &&
        uri.pathSegments[2] == 'releases' &&
        uri.pathSegments[3] == 'download';
  }
}
