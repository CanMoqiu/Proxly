import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'connection_feedback.dart';

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
    throw StateError(failureMessage(value));
  }

  static String failureMessage(dynamic value) {
    if (value is Map && value['state'] == 'api') {
      final status = value['status'];
      if (status == 401 || status == 403) {
        return ConnectionFeedback.authenticationFailed;
      }
      if (status == 502 || status == 503 || status == 504) {
        return ConnectionFeedback.routerUnavailable;
      }
      return '控制器请求失败，请检查地址、端口及 Clash 运行状态。';
    }
    if (value is Map && value['state'] == 'network') {
      return ConnectionFeedback.routerUnavailable;
    }
    return '面板脚本未能完成初始化，请重试';
  }

  static String readinessScript(String secondaryPath) => '''
const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), 8000);
try {
  const response = await fetch(${jsonEncode('$secondaryPath/version')}, {
    signal: controller.signal, cache: 'no-store'
  });
  if (!response.ok) return {state: 'api', status: response.status};
  const data = await response.json();
  if (typeof data.version !== 'string') return {state: 'invalid_response'};
} catch (_) {
  return {state: 'network'};
} finally {
  clearTimeout(timer);
}
const deadline = Date.now() + 10000;
while (!document.querySelector('#app-content') && Date.now() < deadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}
return {state: document.querySelector('#app-content') ? 'ready' : 'app_timeout'};
''';
}
