// Run inside the real bundled panel so Zashboard's document touch handlers
// participate. Synthetic events verify cancellation, not native scroll physics.
const webPanelScrollProbe = r'''
  const host = document.querySelector('#app-content');
  if (!host) throw new Error('Panel is not mounted');
  const scroller = document.createElement('div');
  scroller.className = 'overflow-auto';
  scroller.style.cssText =
    'position:fixed;top:30px;left:20px;width:180px;height:200px;z-index:99999';
  const content = document.createElement('div');
  content.style.cssText = 'height:1000px;width:1000px';
  scroller.appendChild(content);
  host.appendChild(scroller);

  function send(type, points) {
    const touches = points.map(([x, y], identifier) => ({
      identifier, target: content, clientX: x, clientY: y,
      pageX: x, pageY: y, screenX: x, screenY: y
    }));
    // WebKit does not expose a constructible Touch on every platform.
    const event = new Event(type, { bubbles: true, cancelable: true });
    Object.defineProperties(event, {
      touches: { value: type === 'touchend' ? [] : touches },
      targetTouches: { value: type === 'touchend' ? [] : touches },
      changedTouches: { value: touches }
    });
    content.dispatchEvent(event);
    return event.defaultPrevented;
  }
  function sequence(points) {
    send('touchstart', [points[0]]);
    const cancelled = points.slice(1).map(point => send('touchmove', [point]));
    send('touchend', [points[points.length - 1]]);
    return cancelled;
  }
  try {
    scroller.scrollTop = 0;
    const top = sequence([[60, 100], [60, 150], [60, 180], [60, 160]]);
    scroller.scrollTop = scroller.scrollHeight - scroller.clientHeight;
    const bottom = sequence([[60, 200], [60, 150], [60, 120], [60, 140]]);
    const horizontal = sequence([[60, 150], [100, 150], [140, 150], [120, 150]]);
    send('touchstart', [[60, 100], [120, 100]]);
    const multi = send('touchmove', [[60, 150], [120, 150]]);
    send('touchend', [[60, 150], [120, 150]]);
    return { top, bottom, horizontal, multi,
      overscroll: getComputedStyle(scroller).overscrollBehaviorY,
      preference: localStorage.getItem('config/disable-pull-to-refresh') };
  } finally {
    scroller.remove();
  }
''';
