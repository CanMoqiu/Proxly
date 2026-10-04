import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebPanelPageProbe {
  WebPanelPageProbe._();

  // Removing the configurable property makes the standard `in navigator`
  // feature check false. Returning undefined from a getter does not.
  static const disableServiceWorker = r'''
(() => {
  let owner = navigator;
  while (owner) {
    const descriptor = Object.getOwnPropertyDescriptor(owner, 'serviceWorker');
    if (descriptor) {
      if (descriptor.configurable) delete owner.serviceWorker;
      break;
    }
    owner = Object.getPrototypeOf(owner);
  }
})();
''';

  static Future<void> waitUntilReady(
    InAppWebViewController controller,
    String secondaryPath,
  ) async {
    final result = await controller
        .callAsyncJavaScript(
          functionBody: readinessScript(secondaryPath),
        )
        .timeout(const Duration(seconds: 22));
    final value = result?.value;
    if (value is Map && value['state'] == 'ready') return;
    if (value is Map && value['state'] == 'api') {
      throw StateError('控制器连接失败 (HTTP ${value['status']})，请检查地址和 Token');
    }
    if (value is Map && value['state'] == 'network') {
      throw StateError('面板无法连接本地服务或控制器，请重试');
    }
    throw StateError('面板脚本未能完成初始化，请重试');
  }

  static String readinessScript(String secondaryPath) => '''
const deadline = Date.now() + 10000;
while (!document.querySelector('#app-content') && Date.now() < deadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}
if (!document.querySelector('#app-content')) return {state: 'app_timeout'};
const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), 8000);
try {
  const response = await fetch(${jsonEncode('$secondaryPath/version')}, {
    signal: controller.signal, cache: 'no-store'
  });
  if (!response.ok) return {state: 'api', status: response.status};
  const data = await response.json();
  return {state: typeof data.version === 'string' ? 'ready' : 'invalid_response'};
} catch (_) {
  return {state: 'network'};
} finally {
  clearTimeout(timer);
}
''';
}
