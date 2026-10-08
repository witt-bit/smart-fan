# Logo 与品牌资源

整套资源来自同一个品牌包（Applore 生成），**保持原始目录结构**，便于日后网站、App Store
或 Xcode 工程直接取用。各目录的详细用途见品牌包自带的 [品牌包说明.md](品牌包说明.md)。

| 目录 | 用途 |
|---|---|
| `macos/AppIcon.appiconset/` | **应用图标的来源**：macOS 10 个尺寸，小尺寸单独简化过 |
| `ios/AppIcon.appiconset/` | iOS 图标，含深色 / 着色变体（iOS 18+） |
| `ios/AppStore-1024.png` | App Store Connect 提交用图 |
| `web/` | 网站与 PWA：favicon(.ico/.svg)、apple-touch-icon、192/512 PNG、maskable、webmanifest |
| `svg/` | 矢量：完整标志、图形符号、单色黑/白（菜单栏模板图用） |
| `icon-composer/AppIcon.icon/` | Xcode 26 Icon Composer 源文件（Liquid Glass，多平台一份） |

README 顶部的 logo 用的是 `web/icon-192.png`（20KB，192×192）。

## 生成 macOS 应用图标

```bash
scripts/setup.sh icon    # 从 macos/AppIcon.appiconset 生成 SmartFan.icns
scripts/setup.sh app     # 装配到 .app
```

`iconutil` 只接受**目录名以 `.iconset` 结尾**，而这里沿用 Xcode 的 `.appiconset`，
所以 `setup.sh icon` 会先复制到临时目录再转换，**不改动原文件**（否则 Xcode 打不开它）。

## 改完图标后校验一次

```bash
rm -rf /tmp/c.iconset && iconutil -c iconset SmartFan.icns -o /tmp/c.iconset
```

两条硬性要求：每帧的像素尺寸必须等于文件名声明的值；**四角 alpha 必须为 0**
（macOS 不会替第三方图标加圆角，四角不透明就是 Dock 里一个方块）。

## 为什么不用 scripts/generate-icon.swift

它用**一个母版渲染所有尺寸**，所以 16px 必然是糊的——实测图形笔画只占其宽度的 6%，
换算到 16px 就是 0.87px，亚像素必然消失；把母版放大 4 倍也完全一样（比例不变）。
它已降级为试验/预览工具。正式图标请改 `macos/AppIcon.appiconset`，那里每个尺寸是分别设计的。

## 回退到旧图标

```bash
git show <换图标前的提交>:SmartFan.icns > SmartFan.icns
```
