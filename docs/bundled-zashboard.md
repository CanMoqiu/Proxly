# 内置 Zashboard

**简体中文** · [English](bundled-zashboard.en.md) · [文档目录](README.md)

- 版本：v3.30.0（2026-10-29）
- 官方发布：https://github.com/Zephyruso/zashboard/releases/tag/v3.30.0
- 对应提交：`bf4f00bb8d905f8a78f627af7cf84457c4db53c4`
- 资源：官方 `dist.zip`，SHA-256：
  `1f91c014e61e768240a86ad0a9bd565b247ec5a0e26b125fb5d19076682905b7`
- `assets/web_panel` 保留发行资源原样，并补入上游 MIT `LICENSE`。

Proxly 的主题、认证、底栏和字体适配通过独立注入脚本完成，不修改压缩后的
上游 JavaScript。代理和连接标签页隐藏 Zashboard 自带底栏；独立控制台保留。
隐藏底栏保留位于视口底部的零高度定位框，让上游虚拟列表正确计算底部留白。
iOS 旗帜字体由应用自己的资源路径提供，切换为下载的面板后仍然有效。

嵌入面板由 WebView 原生设置和 CSS 控制边缘回弹。Proxly 接管
`config/disable-pull-to-refresh` 并设为 `false`，禁用 v3.30.0 中以最初触点
判断方向的全局 `touchmove` 拦截，避免滑到边缘后反向滑动仍被阻止。
此适配用于代理页、连接页和独立控制台，并在面板更新、配置导入和重载后生效；
保留浏览器原生滚动、惯性与嵌套列表处理，不修改上游压缩资源。

Proxly 同时固定关闭 `config/swipe-in-pages` 和 `config/swipe-in-tabs`，
避免左右滑动改变代理、连接和控制台的页面内容；页面内按钮与应用底栏仍可正常切换。

iOS 代理标签页保留 WebView 原生历史返回手势，同时关闭面板顶层路由的滑动和淡入淡出动画，
避免从规则返回代理后再次播放网页转场；面板内弹窗和列表动画不受影响。

代理页右上角导入入口提供“从内核导入”和“从本地导入 JS 文件”。
内核导入读取 Zashboard 使用的 `/storage/zashboard` 接口，需内核支持且已保存配置。
本地导入接受 Zashboard JSON 配置数据（`.json` 或 `.js` 扩展名），不执行 JavaScript 程序。
两种来源共用大小、结构、凭据过滤及应用托管设置保护，导入后同步刷新存活面板。
