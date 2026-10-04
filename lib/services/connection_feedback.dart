import 'app_platform.dart';

class ConnectionFeedback {
  ConnectionFeedback._();

  static String get unavailable => AppPlatform.isIOS
      ? '请检查控制器地址、网络连接，以及系统设置中的 Proxly 局域网权限。'
      : '无法连接控制器，请检查地址和端口';
}
