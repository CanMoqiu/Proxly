enum RouterTool {
  openClash,
  nikki,
  generic;

  String get label => switch (this) {
        openClash => 'OpenClash',
        nikki => 'Nikki',
        generic => 'Clash API',
      };
  bool get supportsSshManagement => this != generic;
  String get uciPackage => switch (this) {
        openClash => 'openclash',
        nikki => 'nikki',
        generic => throw UnsupportedError('No router adapter selected'),
      };
  String get uploadDirectory => switch (this) {
        openClash => '/etc/openclash/config',
        nikki => '/etc/nikki/profiles',
        generic => throw UnsupportedError('No YAML adapter selected'),
      };
  List<String> get configDirectories => switch (this) {
        openClash => const [
            '/etc/openclash/config',
            '/openclash/config',
            '/etc/clash/config',
            '/root/.config/clash/config'
          ],
        nikki => const ['/etc/nikki/profiles', '/etc/nikki/subscriptions'],
        generic => const [],
      };
  String get restartCommand =>
      '[ -x /etc/init.d/$uciPackage ] && /etc/init.d/$uciPackage restart';

  static RouterTool parse(String? value) => switch (value) {
        'nikki' => nikki,
        'generic' => generic,
        null || 'openClash' => openClash,
        _ => generic,
      };
}

enum ProxyCore {
  unknown,
  clash,
  mihomo;

  String get label => switch (this) {
        unknown => '未识别内核',
        clash => 'Clash',
        mihomo => 'Mihomo',
      };
  static ProxyCore parse(String? value) =>
      values.where((core) => core.name == value).firstOrNull ?? unknown;
}
