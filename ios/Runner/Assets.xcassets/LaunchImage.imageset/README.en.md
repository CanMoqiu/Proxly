# Launch screen assets

[简体中文](README.md) · **English** · [Documentation](../../../../docs/README.en.md)

The launch screen uses `LaunchImage.pdf`, a 96-point icon with a 22-point rounded clipping path. The PDF embeds the existing `LaunchImage@3x.png` artwork unchanged; Xcode rasterizes it for each device scale. The PNG files remain source references.

The rounded shape is part of the asset because launch storyboards cannot use runtime attributes such as `layer.cornerRadius`. The app name is a native label in `Base.lproj/LaunchScreen.storyboard`, keeping text sharp at every screen scale.

To regenerate the PDF after changing the source artwork, install Python's `reportlab` package and run `python scripts/generate_ios_launch_icon.py` from the repository root. This is an asset-authoring step, not a build dependency.
