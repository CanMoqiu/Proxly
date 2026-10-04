import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import '../main.dart';
import '../services/app_secure_storage.dart';
import '../services/clash_service.dart';
import '../theme/app_theme.dart';

/// Keep a retryable UI alive if iOS temporarily denies access to the Keychain.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key, this.initialize});

  final Future<bool> Function()? initialize;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  late Future<bool> _startup = (widget.initialize ?? _initialize)();

  Future<bool> _initialize() async {
    await AppLocaleController.instance.load();
    await ClashService.instance.loadConfig();
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('clash_host') ?? '').isEmpty;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ProxlyApp(showSetupWizard: snapshot.data!);
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr(snapshot.error
                                        is SecureStorageUnavailableException
                                    ? '凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。'
                                    : '启动失败，请重试。已保存的配置未被删除。'),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => setState(() {
                                  _startup =
                                      (widget.initialize ?? _initialize)();
                                }),
                                child: Text(tr('重试')),
                              ),
                            ],
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
