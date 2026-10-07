# 内置 Zashboard

- 版本：v3.29.1（2026-09-23）
- 官方发布：https://github.com/Zephyruso/zashboard/releases/tag/v3.29.1
- 对应提交：`50717b02dac68425cdc5b80cb754bea768ee4fc9`
- 资源：官方 `dist.zip`，SHA-256：
  `4f16cce229e223bd07b5a3daccfbfb8bf349d7335572d412959284ab6c9bab50`
- `assets/web_panel` 保留发行资源原样，并补入上游 MIT `LICENSE`。

Proxly 的主题、认证、底栏和字体适配通过独立注入脚本完成，不修改压缩后的
上游 JavaScript。代理和连接标签页隐藏 Zashboard 自带底栏；独立控制台保留。
隐藏底栏保留位于视口底部的零高度定位框，让上游虚拟列表正确计算底部留白。
iOS 旗帜字体由应用自己的资源路径提供，切换为下载的面板后仍然有效。

嵌入面板由 WebView 原生设置和 CSS 控制边缘回弹。Proxly 接管
`config/disable-pull-to-refresh` 并设为 `false`，禁用 v3.29.1 中以最初触点
判断方向的全局 `touchmove` 拦截，避免滑到边缘后反向滑动仍被阻止。
此适配用于代理页、连接页和独立控制台，并在面板更新、配置导入和重载后生效；
保留浏览器原生滚动、惯性与嵌套列表处理，不修改上游压缩资源。
