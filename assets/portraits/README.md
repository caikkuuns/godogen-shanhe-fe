# 立绘（2D 头像）

对话面板与 HUD 的 2D 头像统一从这个目录取，**不要再指向 `docs/`**——
`docs/` 不进导出包（见 `EXPORT.txt`），指向它的路径在出包后必然静默失效，
这正是第10轮报告里的 P0「立绘路径硬编码、`ResourceLoader.exists()` 为假时无回退」。

| 文件 | 状态 | 来源 |
| --- | --- | --- |
| `linzhaowan_portrait.png` | ✅ 真立绘 | `assets/imported/portraits/linzhaowan_portrait_smile_v2.png` |
| `gesancheng_portrait.png` | ✅ 真立绘 | `assets/imported/portraits/gesancheng_portrait_default.png` |
| `shenyan_portrait.png` | ⚠️ 占位图 | 待替换，图为「沈」字样色块 |
| `zhoubo_portrait.png` | ⚠️ 占位图 | 待替换 |
| `mingcheng_portrait.png` | ⚠️ 占位图 | 待替换 |
| `liheng_portrait.png` | ⚠️ 占位图 | 待替换 |
| `unknown_portrait.png` | ⚠️ 兜底图 | 其他 NPC 无立绘时用它 |

约定：

- 尺寸 640×800 上下、RGBA、正面半身，头部落在画面上方 1/3。
- HUD 头像取 `Rect2(90, 40, 480, 480)` 这块做裁切，所以头肩要落在这个范围内。
- 新增 NPC 时在 `scripts/world/open_world.gd` 的 `PORTRAITS` 里加一行；缺图自动回退到 `unknown_portrait.png`。
- 占位图保留「PLACEHOLDER(占位)」水印，避免被误当成定稿素材。
