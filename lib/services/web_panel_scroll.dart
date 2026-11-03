/// Native WebViews and CSS own overscroll suppression in the embedded panel.
/// Zashboard 3.29's touchmove guard compares against touchstart and keeps
/// cancelling a gesture after the finger reverses at a scroll boundary.
/// Page and tab swipes are disabled because Flutter owns top-level navigation.
class WebPanelScroll {
  static const managedPreference = 'config/disable-pull-to-refresh';

  /// WebKit already animates history navigation; suppress the SPA's second slide.
  static const nativeHistoryTransitions = r'''
    (function() {
      function apply() {
        if (!document.documentElement ||
            document.getElementById('__proxly_native_history')) return;
        const style = document.createElement('style');
        style.id = '__proxly_native_history';
        style.textContent = `
          #app-content .home-page > .relative.flex-1 > .absolute > :is(
            [class*="slide-left-"], [class*="slide-right-"],
            [class*="page-enter-"], [class*="page-leave-"]
          ) {
            transition: none !important;
            transform: none !important;
            opacity: 1 !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      }
      document.addEventListener('DOMContentLoaded', apply, { once: true });
      apply();
    })();
  ''';

  static String buildScript() => r'''
    (function() {
      const stateKey = '__proxlyNativeScrollV1';
      if (window[stateKey]) {
        window[stateKey]();
        return;
      }
      const keys = [
        'config/disable-pull-to-refresh',
        'config/swipe-in-pages',
        'config/swipe-in-tabs'
      ];
      function apply() {
        for (const key of keys) {
          const oldValue = localStorage.getItem(key);
          if (oldValue !== 'false') {
            localStorage.setItem(key, 'false');
            // Also update a mounted panel after preferences are restored/imported.
            window.dispatchEvent(new StorageEvent('storage', {
              key, oldValue, newValue: 'false', storageArea: localStorage
            }));
          }
        }
        if (!document.documentElement) return;
        if (document.getElementById('__proxly_native_scroll')) return;
        const style = document.createElement('style');
        style.id = '__proxly_native_scroll';
        style.textContent = `
          html, body { overscroll-behavior: none !important; }
          #app-content .overflow-y-auto,
          #app-content .overflow-y-scroll,
          #app-content .overflow-auto {
            overscroll-behavior: none !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      }
      window[stateKey] = apply;
      function preferenceChanged(event) {
        const change = event.detail || event;
        if (change.storageArea === localStorage &&
            (keys.includes(change.key) || change.key === null)) {
          // VueUse writes its ref before emitting this event. Reset on the next
          // microtask so its storage listener can update that ref without a loop.
          queueMicrotask(apply);
        }
      }
      window.addEventListener('storage', preferenceChanged);
      window.addEventListener('vueuse-storage', preferenceChanged);
      document.addEventListener('DOMContentLoaded', apply, { once: true });
      apply();
    })();
  ''';
}
