/// Native WebViews and CSS own overscroll suppression in the embedded panel.
/// Zashboard 3.29's touchmove guard compares against touchstart and keeps
/// cancelling a gesture after the finger reverses at a scroll boundary.
class WebPanelScroll {
  static const managedPreference = 'config/disable-pull-to-refresh';

  static String buildScript() => r'''
    (function() {
      const stateKey = '__proxlyNativeScrollV1';
      if (window[stateKey]) {
        window[stateKey]();
        return;
      }
      const key = 'config/disable-pull-to-refresh';
      function apply() {
        const oldValue = localStorage.getItem(key);
        if (oldValue !== 'false') {
          localStorage.setItem(key, 'false');
          // Also update a mounted panel after preferences are restored/imported.
          window.dispatchEvent(new StorageEvent('storage', {
            key, oldValue, newValue: 'false', storageArea: localStorage
          }));
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
            (change.key === key || change.key === null)) {
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
