# Proxly 26.6 发布前安全审查

审查日期：2026-10-02。基线：`beta@25d0744`，比较对象：`72286c3`（26.5）。重点审查 3 个 beta 提交涉及的 SSH/UCI/YAML 操作、控制器认证、WebView 导入桥接、资源更新及敏感信息处理。本文不代表对路由器固件或第三方依赖进行过完整渗透测试。

## 发现与修复

### P1：以 root 权限反序列化任意 Ruby 对象

原 `openclash_quick_settings_service.dart:1182–1187,1343–1348` 在读取运行时 YAML 时调用 `unsafe_load_file`，兼容分支使用的 OpenClash `YAML.rb` 也将 `load` 别名指向 `unsafe_load`。如果攻击者能使带 Ruby 类型标签的配置进入被读取的本地 YAML，打开快捷设置或修改嗅探/DNS 设置就会触发对象构造；影响取决于路由器上可用的 Ruby 类和回调。顶层 Hash 检查发生在反序列化后，不能阻止嵌套对象构造。不能据此断言任意远程用户都能攻击设备。

修复：在加载 OpenClash 兼容模块后覆盖其反序列化入口，使用 `safe_load`；只额外允许无执行回调的 Date/Time 值并保留 YAML 锚点，不允许任意 Ruby 对象和 Symbol。保留兼容模块的文本修正、解密及写入能力。回归测试使用只会抛出标记异常的测试类，验证对象回调未执行，以及系统和兼容加载路径均保留锚点。

参考：[Ruby Psych 安全加载说明](https://ruby-doc.org/stdlib-3.1.1/libdoc/psych/rdoc/Psych.html)、[OpenClash YAML 兼容模块](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/root/usr/share/openclash/YAML.rb)。

### P2：临时配置备份未限制权限

原 `openclash_quick_settings_service.dart:922,1438–1447` 将 UCI 和运行时配置写入 `/tmp/proxly_时间戳.*`，没有设置 umask 或私有目录。在常见 umask 022 下，同机其他用户可以读取含控制器密钥、订阅信息的备份；连接中断还可能留下备份。时间戳名称也没有排除预置同名文件/符号链接。该问题在 26.5 的事务路径已存在，beta 新增运行模式保存路径沿用了它。

修复：使用随机事务目录、原子 `mkdir`、目录 0700 和 umask 077；目录已存在即拒绝操作，不跟随预置符号链接。恢复和清理复用同一目录。Ruby 临时写入使用排他创建和初始权限 0600，仅清理本次成功创建的临时文件。Linux 回归验证目录/文件权限以及符号链接拒绝行为。

### P2：诊断信息脱敏遗漏 JSON 和带空格的凭据

原 `openclash_quick_settings_service.dart:1048–1061` 的正则无法匹配 `{"password":"..."}`，对 `secret: "带空格的值"` 也只替换第一段，残留值会进入错误详情和 Debug 日志。用虚构凭据在本地复现，未读取真实设备数据。

修复：统一过滤带引号的字段、完整带空格的值和 `dashboard_password` 等复合字段名，增加 JSON/YAML/UCI 与转义引号测试。诊断仍限制长度并过滤 URL、Bearer 和地址；不将此视为任意文本中秘密均可被识别的保证。

## 其他检查

- beta 的快捷设置已改用应用配置的控制器地址与 Token；运行模式使用受协调的重启流程；枚举映射约束写入项。
- SSH 主机指纹首次确认及变更确认仍存在，密码没有插入远端 shell 命令。
- 文件路径范围、面板 ZIP 大小/路径/符号链接/摘要校验，以及导入配置敏感字段过滤仍存在。
- Zashboard v3.25.0 官方 `dist.zip` SHA-256：`98bb75a3df37a9ece122ec43d65515ccad93254e020eaf2b3ae2a3859bcf4d42`。321 个内置文件逐一比对，仅有 Git 换行格式差异，无额外或缺失文件。该核验确认来源一致，不等同于第三方面板全部代码无漏洞。
- 26.6 仅发布源码和说明，不上传 APK。构建验证产物仅保存日志。

## 验证范围

本地使用 Flutter 3.47.5 进行静态检查和 Flutter 回归；Ruby 行为和 POSIX 权限测试在 Linux CI 执行，Windows 上明确跳过。Android Debug 构建作为共享代码与依赖回归检查。真实路由器差异和 iOS Web/SSH 问题仍需后续真机验证，本次 Android 源码发布不声称已解决 iOS 故障。
