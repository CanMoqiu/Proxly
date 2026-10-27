# 启动页资源

**简体中文** · [English](README.en.md) · [文档目录](../../../../docs/README.md)

启动页使用 `LaunchImage.pdf`：96 点图标，带 22 点圆角裁剪路径。PDF 原样嵌入已有的 `LaunchImage@3x.png` 图案，由 Xcode 按设备倍率栅格化。PNG 文件保留作为源图参考。

圆角直接包含在资源中，因为启动页 storyboard 不能使用 `layer.cornerRadius` 之类的运行时属性。应用名称是 `Base.lproj/LaunchScreen.storyboard` 中的原生标签，在各屏幕倍率下保持文字清晰。

修改源图后，在 Python 环境安装 `reportlab`，再从仓库根目录运行 `python scripts/generate_ios_launch_icon.py` 重新生成 PDF。这是资源制作步骤，不是构建依赖。
