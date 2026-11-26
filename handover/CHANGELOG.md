# 改动记录

按时间倒序。每次改动一行，详细说明另写成 `交接-YYYYMMDD-谁-主题.md`。

---

## 2026-11-24

### 001 · 建立 GitHub 私有仓库并推送项目
- **谁**：萧炎（Lead）
- **仓库**：https://github.com/caikkuuns/godogen-shanhe-fe（private）
- **提交**：`33b6914` 源码与资源 → `d279769` 补入 assets
- **范围**：428 个文件 / 107.6 MB
  - 全部 GDScript（`scripts/`）、场景（`scenes/`）、着色器（`shaders/`）、数据（`data/`）、文档（`docs/`）、测试（`tests/`）、工具（`tools/`）
  - `assets/glb/` 6 个原版 GLB + 6 个 opt 精简版 + 全部贴图
  - `assets/fonts/shanhe_serif.otf`（23.3 MB）、`assets/branding/` 图标
- **排除**：`incoming/`（410 MB TripoSR 中间产物）、`captures/`（截图）、`docs/ref-characters*`（51 MB 参考图）、`generated/`、`backups/`
- **验证**：未登录访问 API 返回 404；`private: true`；未在任何文件中发现服务器密码 / IP / 令牌
- **来源**：服务器 `<project>`，HEAD `55cb7b3`（第十轮地形亮度校准）

### 已进仓库的关键改动（来自服务器历史）
| 提交 | 内容 |
|---|---|
| `55cb7b3` | 第十轮地形亮度校准：`chunk_builder.gd:65` `_terrain_mat.albedo_color = Color(1.92, 1.87, 2.23)`，改后亮度 lum 117.8 vs 目标 118.2 |
| （工作区） | `character_model.gd` 接入 `shenyan_hero.glb`，近景走 hero、战斗走旧 `shenyan.glb` |

---

## 待办（按优先级）

1. **P0-1**：修白袍贴图大面积破碎（疑 UV 岛重叠或贴图导出损坏）
2. **P0-2**：修面部贴图错位（白色横条穿五官、发髻白色碎块）
3. **P1-3**：冷色饰边调暖 —— `trim_ice` `#658CC2`→`#9FB6CE`、`sash_tail` 剪短到 Y 0.8 以上、`boot_grey`→`#3A3A3A`
4. **硬指标**：产出 `captures/kimi_walk_00.png` ~ `kimi_walk_07.png` 8 帧
5. **验收**：转台 4 角度 + 近景 + walk 8 帧判定
6. **出包**：APK

---

## 已知问题

- 服务器 SSH 偶发在 banner 阶段被断（SSH banner 阶段被断）
- 团队的 DS Bot 权限预设需用户在 UI 手动设成「完全权限」，否则每次执行命令都要点通过
