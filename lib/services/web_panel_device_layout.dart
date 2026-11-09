import 'dart:convert';

class WebPanelDeviceLayout {
  WebPanelDeviceLayout._();

  static const desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

  static String tablet({bool embedded = true}) {
    final css = embedded
        ? 'html.__proxly_tablet .home-page > div:has(> .sidebar) { display: none !important; }'
        : '';
    return '''
(() => {
  if (window.__proxlyTabletLayout) return;
  window.__proxlyTabletLayout = true;
  // Override only Zashboard's compact-layout query, including 768px iPads.
  const matchMedia = window.matchMedia.bind(window);
  window.matchMedia = function(query) {
    if (query.replace(/\\s/g, '') !== '(max-width:768px)') return matchMedia(query);
    return {
      matches: false, media: query, onchange: null,
      addListener() {}, removeListener() {},
      addEventListener() {}, removeEventListener() {},
      dispatchEvent() { return true; }
    };
  };
  function apply() {
    document.documentElement.classList.add('__proxly_tablet');
    if (document.getElementById('__proxly_tablet_style')) return;
    const style = document.createElement('style');
    style.id = '__proxly_tablet_style';
    style.textContent = ${jsonEncode(css)};
    (document.head || document.documentElement).appendChild(style);
  }
  if (document.documentElement) apply();
  else document.addEventListener('DOMContentLoaded', apply, {once: true});
})();
''';
  }
}
