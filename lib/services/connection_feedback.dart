import 'app_platform.dart';
import 'clash_service.dart';

class ConnectionFeedback {
  ConnectionFeedback._();

  static const routerUnavailable =
      '暂时无法连接软路由。请连接软路由所在网络，并确认 Clash 已启动。连接恢复后会自动重试。';
  static const authenticationFailed = '控制器认证失败，请在设置中检查 Token。';

  static String forError(Object error) {
    if (error is ClashControllerException) {
      return switch (error.kind) {
        ClashControllerFailureKind.notConfigured => '请先在设置页填写 Clash 地址',
        ClashControllerFailureKind.unauthorized => authenticationFailed,
        ClashControllerFailureKind.timeout ||
        ClashControllerFailureKind.unreachable =>
          routerUnavailable,
        _ => '控制器请求失败，请检查地址、端口及 Clash 运行状态。',
      };
    }
    return '读取控制器数据失败，请重试。';
  }

  static String get unavailable => AppPlatform.isIOS
      ? '请检查控制器地址、网络连接，以及系统设置中的 Proxly 局域网权限。'
      : '无法连接控制器，请检查地址和端口';
}
