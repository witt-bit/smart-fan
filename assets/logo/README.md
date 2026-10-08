# Logo

| 文件 | 作用 |
|---|---|
| `smart-fan-mark.svg` | **图标母版**，`scripts/generate-icon.swift` 用它生成所有尺寸 |
| `smart-fan-mark.png` | 最初生成的原稿（1254×1254，白底），仅留档 |
| `preview/` | 每次生成时的预览（可随时重跑得到，已 gitignore） |

## 当前的图标外观

**透明底**：图标就是图形本身，没有底块——四角透明，因此在 Dock / Finder 里
呈现的是图形轮廓，而不是一个方块。图形占底块位宽的 92%。

母版由 VTracer 从原稿描摹而来（199 条路径、约 170 种抗锯齿色），所以它是
**矢量**：任何尺寸都按几何重建，不会因放大而模糊。描摹保留的是原造型
（7 个分离元素、笔画占 6%），因此 **16px 仍然偏细** —— 这是造型问题，不是分辨率问题。

## 更换图标

```bash
# 1) 放一张新母版（同时改 scripts/generate-icon.swift 的默认路径，或用 --master 指定）
#    要求：白底或透明底的**图形本身**（不要底块、不要文字），≥1024px，图形内部不要有封闭白区
swift scripts/generate-icon.swift --master 新母版.svg --preview assets/logo/preview
open assets/logo/preview/zoom-16px.png      # 先看小尺寸
scripts/setup.sh icon                       # 确认后生成 icns
scripts/setup.sh app                        # 装配
```

可选参数：`--tile light|none|#RRGGBB`（默认 `none` 透明）、`--tint #RRGGBB`（把图形改成单色）、
`--fill 0…1`（图形占位宽比例，默认 0.92）、`--small-master`（小尺寸用简化母版）。

## 回退

旧图标仍在 git 历史里：

```bash
git show fd75a59:SmartFan.icns > SmartFan.icns   # 旧橙色风扇图标
```
