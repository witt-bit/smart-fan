# Logo 与图标

## 文件

| 路径 | 作用 |
|---|---|
| `AppIcon.appiconset/` | **图标来源**：10 个尺寸（16/32/128/256/512 各 @1x @2x），小尺寸是单独简化过的版本 |
| `svg/logo.svg` | 完整标志（6 路径 / 4 色，1024 视框） |
| `svg/logo-symbol.svg` | 图形符号（用于菜单栏等场合） |
| `svg/logo-mono-black.svg` · `logo-mono-white.svg` | **单色版**，菜单栏模板图用 |
| `icon-source/` | Icon Composer 源文件（Background/Foreground + icon.json），用于重新导出 appiconset |
| `品牌包说明.md` | 原始品牌包自带的说明 |

## 生成图标

```bash
scripts/setup.sh icon    # 从 AppIcon.appiconset 生成 SmartFan.icns
scripts/setup.sh app     # 装配到 .app
```

`iconutil` 只接受**目录名以 `.iconset` 结尾**，而 Xcode 的约定是 `.appiconset` ——
所以 `setup.sh icon` 会先复制到临时目录再用 `iconutil`，不改动原始文件（否则 Xcode 打不开它）。

## 为什么不用 `scripts/generate-icon.swift`

那个脚本**用一个母版渲染所有尺寸**，因此 16px 必然是糊的（图形细节在 16px 下只有亚像素）。
它已降级为试验/预览工具：`swift scripts/generate-icon.swift --master <文件> --preview <目录>`。
正式图标请用 `AppIcon.appiconset` —— 里面每个尺寸是分别设计/简化的。

## 校验（改图标后跑一下）

```bash
rm -rf /tmp/c.iconset && iconutil -c iconset SmartFan.icns -o /tmp/c.iconset
# 每帧尺寸必须等于其名字声明的像素，且四角 alpha 必须为 0（macOS 不会替你加圆角）
```

## 回退

旧图标在 git 历史里：`git show <上一个提交>:SmartFan.icns > SmartFan.icns`
