# 《山河剑行》视觉评审 + 可执行美术参数 v1

> 评审对象：`art/_inputs/`（改造前基线截图 960×540 + 源码快照 + ref-characters-v2）。
> 只读评审，未改项目任何文件。项目侧键名以快照代码为准；截图是 960×540，下文 `@960` 指该分辨率，设计值指 1920×1080。
> 一句话：**画面空不是缺素材，是相机把 6m 外的一切裁掉了；过曝发灰是 Environment 数值问题；2.5D 感要先落人物规范再谈风格。**

---

## 0. 三条结论（先看这个）

1. **相机是第一优先级**：俯角 45°（`offset=(0,7.4,7.4)`）+ FOV 32 → 画面顶边射线只到相机前方约 13m（角色前方 5–6m），门楼/村舍/竹林/远山全部出画，剩下 ≥80% 纯地面色块。
   → 目标：俯角 38°、FOV 38、距离 11.8m、`look_height 1.15`。同一场景即可同时看到地面、门楼、屋脊、雾化远景。
2. **过曝/发灰是数值问题**：exposure 0.95 + ambient 0.46 + sat 1.06 → 地面中心实测 ≈`#EDE9CF`（接近白），最暗处仅 `#4A4A3A`，对比 <10%。
   → 目标：exposure 0.82、tonemap_white 8.0、ambient 0.34、contrast 1.10、fog 改 DEPTH 模式；并给画面加 1 个暗锚点（深瓦/木构/树影）。
3. **2.5D 感靠人物规范落地**：v2 素材 420×500、锚点 (210,476)、`pixel_size=0.00386`、`BILLBOARD_FIXED_Y` + `shaded=false` + blob shadow。当前代码还在用 v1 四方向素材、`pixel_size=0.00474`，先把规范切过来，风格才谈得上。

---

## 1. 逐图诊断

### 1.1 explore.png（探索主视图）

| 项 | 证据（@960） | 结论 / 改法 |
|---|---|---|
| 相机 | 俯角 45°，FOV 32，距离 10.5m | 顶边只照到角色前 5–6m，建筑全出画 → §3 |
| 构图 | 角色在正中心 (480,270)，脚底线 55% | 空；四角被 HUD 占满，视线无落点 → §3/§9 |
| 角色占比 | 1.70m ≈ 145px（27%） | 偏大且无层次；目标 17–20% → §3 |
| 地面 | 中心 ≈`#EDE9CF`，亮部 ≈`#F5F1DE`，阴影 ≈`#C9C7AE` | 近白、对比 <10%，是"白纸" → §7 |
| 层次 | 只有中景，无远山/天/雾 | 缺三层构图 → §7 远景带 |
| 阴影 | 硬边长影 ≈1.5×身高，色 ≈`#6F6F5F` | 与脚底无接触暗部，漂浮贴纸感 → §5/§10 |
| 2.5D 感 | 人物无轮廓光、无接地暗、无景深 | 白袍与白地同明度 → §10 |
| 左侧灰墙 | 约 120px 宽灰色平面 | `_build_mounds` 的 34×9×30 球体（world_builder.gd:343-354）近景切开，无纹理、边缘硬 → §7 |
| HUD | 头像框全黑；"气血100/100"压在条内；行/图/存/菜 是圆底白字占位；"交谈"是 192px 深橄榄方块 | 六处不一致 → §9 |

### 1.2 dialogue.png

- 同相机问题；左侧灰色岩壁占 1/4 屏（同上 mound 球体）。
- **周伯只有名字 Label3D，身体缺失**：world_builder.gd:970 用 `ref-characters-v3/npc/` 路径，快照里该资源不存在 → Sprite3D 为空。→ 资源校验兜底（§10 迁移清单 5）。
- **白汤圆**：约 (405,195) 浅灰球 = `_build_rocks` 的平滑球体（`#9b8f7c` 无贴图），强光下变白球 → §7 石头改法。
- 对话框：568×150@960（设计 1704×300），深棕 `#2A241E` α0.92 + 1.5px 金边；名字 21px / 正文 22px 可读。
  但：名字与正文只隔 10px（设计值）→ 屏上 5px；右下 ▼ 只有 12px；底部离屏 24px（设计）→ 屏上 12px。
- 中文：宋体已生效（`shanhe_serif.otf`）；正文 44 设计 px → 960 屏 22px，笔画偏细 + outline 3px → 边缘发糊 → §9。

### 1.3 hud.png

- 同 1.1 舞台（周伯仍缺身体，白汤圆仍在）。
- `E · 交谈` 金色 Label3D（font_size 44 / pixel_size 0.0053）悬在周伯名字上方 0.64m；两个 Label 无底板，压在草地上难读 → §10 姓名板规范。
- 顶部菜单栏 `offset_top = 0`，圆角/刘海屏会切掉图标 → §9 安全区 24px。
- 中心 50%×55% 留空是 HUD 的设计意图（hud.gd 注释），但场景里没有前景元素，空得更明显 → §7 前景规则。

---

## 2. 速改参数表（P0，可直接抄）

> 世界是代码生成的（world_builder.gd / player_camera.gd），所以给的是**属性键 = 目标值**，不是 .tscn 文本。分节详细说明见 §3–§9。

```gdscript
# ---- player_camera.gd  ----
offset = Vector3(0.0, 7.27, 9.30)   # 俯角 38° / 距离 11.8m
look_height = 1.15
smoothing = 6.0                     # t = 1 - exp(-6*dt)
fov = 38.0
near = 0.15
far = 160.0
keep_aspect = Camera3D.KEEP_HEIGHT

# ---- world_builder._build_environment() ----
env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
env.tonemap_exposure = 0.82
env.tonemap_white = 8.0             # 越大高光越压得住
env.ambient_light_sky_contribution = 0.45
env.ambient_light_energy = 0.34
env.glow_enabled = true
env.glow_intensity = 0.28
env.glow_bloom = 0.04
env.glow_hdr_threshold = 1.15
env.adjustment_enabled = true
env.adjustment_brightness = 1.00
env.adjustment_contrast = 1.10
env.adjustment_saturation = 1.00
env.fog_mode = Environment.FOG_MODE_DEPTH
env.fog_light_color = Color("#DCE6EE")
env.fog_light_energy = 0.9
env.fog_density = 0.85
env.fog_depth_begin = 16.0
env.fog_depth_end = 58.0
env.fog_aerial_perspective = 0.45
env.fog_sky_affect = 0.55
env.fog_height = 0.9
env.fog_height_density = 0.5

# ---- 主光 / 轮廓光 ----
sun.rotation_degrees = Vector3(-46.0, -132.0, 0.0)
sun.light_color = Color("#FFE8C6")   # ≈5000K
sun.light_energy = 1.18
sun.directional_shadow_max_distance = 42.0
sun.shadow_blur = 1.6
sun.light_angular_distance = 0.9
sun.shadow_bias = 0.05
sun.shadow_normal_bias = 1.5
rim.rotation_degrees = Vector3(-22.0, 40.0, 0.0)
rim.light_color = Color("#D6E4F2")
rim.light_energy = 0.32
```

```gdscript
# ---- 天空（ProceduralSkyMaterial）----
sky_top_color = Color("#A9C0D8")
sky_horizon_color = Color("#E6EAEC")
ground_horizon_color = Color("#C8CBBE")
ground_bottom_color = Color("#5C6258")
sun_angle_max = 24.0
sky_energy_multiplier = 0.8
```

```gdscript
# ---- project.godot（只动这两项）----
scaling_3d/scale = 0.85            # 现 0.75；画质优先再提，30fps 掉帧就回 0.75
anti_aliasing/quality/msaa_3d = 1  # 保持 2×MSAA
```

---

## 3. 相机

### 3.1 目标值

| 键 | 现 | 目标 | 说明 |
|---|---|---|---|
| 俯角 | 45° | **38°** | 立绘按 45–55° 画，38° 是「立绘不违和 + 能看到建筑»的折中 |
| 距离 | 10.5m | **11.8m** | 角色屏高 ≈18% |
| FOV | 32 | **38** | 加大只拉深度，不压扁人物 |
| offset | (0,7.4,7.4) | **(0,7.27,9.30)** | = 11.8·sin38° / 11.8·cos38° |
| look_height | 0.95 | **1.15** | 角色下移到脚底线 58–62% 屏高 |
| smoothing | 7.5 | **6.0** | 更"软"，减少手机跟手抖动感 |
| near / far | 0.12 / 140 | **0.15 / 160** | far 要够到 58m 雾末端 |

### 3.2 构图硬规则（每次截图都按这个核）

- 角色屏高 **17–20%**（1080 下 184–216px；实测公式 `f_y = 540/tan(fov/2)`，`px = f_y × 1.70 / 视深`）。
- 脚底线落在 **58–62%** 屏高。
- 画面顶边必须能看到 **≥1 处高于 3m 的建筑构件**（门楼/屋脊/檐角/竹梢）。
- 画面中心 50%×55% 保持空（HUD 已按此设计），但外围必须有前景（§7）。
- 相机 yaw 固定 0（不要随角色转），否则 8 方向素材映射会失效。

### 3.3 对话相机（进入对话时切，结束后 restore）

```gdscript
offset = Vector3(1.8, 4.53, 6.23)   # 俯角 36° / 距离 7.7m
look_height = 1.25
fov = 34.0
# 角色 ≈32% 屏高，视线 3/4 侧，留出底部对话框
```

---

## 4. 环境：色调 / 雾 / 天空

| 键 | 现 | 目标 | 原因 |
|---|---|---|---|
| tonemap | FILMIC 0.95 / white 6 | **FILMIC 0.82 / white 8.0** | 治过曝；若调完偏暗先回 exposure 0.88（AGX 可选：`TONE_MAPPER_AGX` + exposure 1.0 + white 6.0） |
| ambient | 0.46 / sky 0.55 | **0.34 / 0.45** | 压平光，让明暗有区分 |
| glow | 关 | **开：0.28 / bloom 0.04 / threshold 1.15** | 只给灯笼、白衣、水面一点光晕；white 衣角不能炸 |
| fog | EXP 0.006 + height 1.1/0.2 | **DEPTH：begin 16 / end 58，density 0.85，aerial 0.45** | EXP 全局加白导致"发灰"；DEPTH 只雾远景，保住近景对比 |
| adjustment | sat 1.06 / contrast 1.05 | **sat 1.00 / contrast 1.10** | 饱和度回中，先拿对比度 |
| 天空 | top #9DB7D4 / horizon #DBE3E8 | **top #A9C0D8 / horizon #E6EAEC / 地色 #C8CBBE→#5C6258** | 更冷、更淡，与暖主光分离 |

**禁项（30fps 预算，保持关闭）**：SSAO、SSIL、SDFGI、SSR、体积雾、屏幕空间反射。

**雾色原则**：雾颜色永远比地面亮、比天空暗一档（`#DCE6EE`），不要用纯白；这样远景才有"空气"而不是"糊白"。

---

## 5. 光照与阴影

| 项 | 目标 |
|---|---|
| 主光方向 | `rotation_degrees (-46, -132, 0)`：画面左上打，影子投右下（与 blob shadow 的右下偏置一致） |
| 主光色温 | `#FFE8C6`（≈5000K），energy **1.18** |
| 补光 | 只用环境光（sky contribution 0.45 / energy 0.34），不加第二盏灯 |
| 轮廓光 | 第二盏 DirectionalLight3D：`(-22, 40, 0)`、`#D6E4F2`、**0.32**、`shadow_enabled=false` |
| 阴影模式 | `SHADOW_PARALLEL_2_SPLITS`（Mobile；4 splits 不划算） |
| 阴影距离 | **42m**（现 70，一半性能） |
| 阴影软度 | `shadow_blur 1.6` + `light_angular_distance 0.9` |
| 防彼得潘 | `shadow_bias 0.05` / `shadow_normal_bias 1.5` |
| 灯笼点光 | `OmniLight3D` energy **0.8–1.0**、range **4.0–5.2**、色 `#FFB877`、`shadow_enabled=false` |
| 谁投影 | 只允许：建筑、门楼、石灯、篱笆、井（≈≤20 个 caster）。**人物/竹/草/落叶/雾卡一律 `cast_shadow=OFF`** |

人物的"影"由 §10 的 blob shadow 负责，不再吃实时阴影——这同时解决"影子漂浮"和性能。

---

## 6. 后处理（移动端只加这三样）

| 效果 | 参数 | 做法 |
|---|---|---|
| 暗角 | 强度 **0.30**、起始半径 **0.85**、色 `#10131A`、alpha 上限 0.5 | 全屏 ColorRect + 径向 shader（1 个 pass） |
| 颗粒 | **0.012–0.015** | 256×256 静态噪点贴图，`TEXTURE_FILTER_NEAREST`，平铺，不逐帧随机 |
| 纸纹 | **4–6%** multiply | 同上噪点，低频一点；水墨感来源 |
| 色散 | **关**（0） | 移动端性价比低、容易糊 |
| 景深/移轴 | **关** | 用 §4 的雾做纵深；DOF 在 Mobile 上是全屏 pass，不值 |

全部放在一个 `CanvasLayer(layer=10)` 里，跟随主相机分辨率，不要逐帧 new 资源。

---

## 7. 地面、装饰、层次

### 7.1 地面（治"白纸"）

- 保留现有顶点色大范围变化（`#5F6B37/#7C8749/#485329` 草、`#9B825D/#BFA983` 土），**再加一层贴图**：
  - `albedo_texture = ground_grass_tile / ground_dirt_tile`（docs 里点名的两张）
  - `vertex_color_use_as_albedo = true`（贴图 × 顶点色，二者相乘）
  - UV 世界平铺 **1 tile / 2.5m**，`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`，`roughness 0.97`
- 土路边缘软过渡带 **1.7m**（`path_edge_grass_over_dirt.png`）。
- 广场/演武场是硬土（现有 plaza/clearing 逻辑保留），但要在边缘加 0.15–0.3m 的草侵入。

### 7.2 装饰密度（按可玩走廊 40m×90m 算）

| 元素 | 目标 | 备注 |
|---|---|---|
| 草簇 | **1600** 实例（现 820），高 0.32–0.62m | 60% 集中在 20m 内；`visibility_range_end=34` |
| 竹丛 | 90 → **110 丛** | 每丛 2–4 根，高 7.5–11.8m（现值可保留） |
| 落叶地贴 | **0.6 簇/m²**（仅竹林），单片 0.05–0.12m | MultiMesh，1 批 |
| 碎石 | **0.15 个/m²**、0.08–0.22m | 沿路缘加密 |
| 人物道具卡（r4） | 主路两侧 **4–6m 交替**；可玩区 **每 25m² ≥1 件** | 石灯/篱笆/木箱/路牌/井 |
| 前景遮挡 | 距相机 **2–4m**、在画面左或右 **15% 边缘**，每屏 ≥1 个 | 竹枝/檐角/门柱；不要挡脸 |
| 远景带 | **25–40m** 处 3–5 组 **8–12m** 高的竹/山剪影 + 2 张雾卡 | 填画面顶部 20%，色 `#9AA9B8/#7D8B99` |

### 7.3 石头（治"白汤圆"）

- 删除 `_build_rocks` 的平滑球体（world_builder.gd:600-610）。
- 改：8 块低模岩（顶点抖动 10–15%），尺寸 2.4–3.3m，颜色上下渐变 `#C4B59D`（上）→ `#776D63`（下），底半径 1.2× 高，埋地 0.25m；小石头 34 颗给顶点色（`#B8A590`→`#5D5850`）。
- 或直接用 `assets/props` 风格画石头卡（与 r4 道具同一套笔触），保持 2.5D 统一。

### 7.4 山体（治"左侧灰墙"）

- mound 球体（34×9×30）从 `(-30,-2.5,8)` 移到 **≥45m** 外，或换成 3–5 个低多边形山坡（`PrismMesh` 顶点抖动），色 `#8A9B8E`→`#5E6A63` 渐变 + 雾化 50%。
- 山脚补 8–12m 高竹/松剪影，制造"挡住视线但不挡路"的边界。

---

## 8. 建筑比例（3D 建筑的目标尺寸）

现 `building_factory.gd` 基本达标（门高 2.2m、层高 2.9–3.05m），补这几条：

| 项 | 目标值 | 现值 |
|---|---|---|
| 台基高 | 0.45m | 0.45 ✓ |
| 层高 | 3.0m（±0.05） | 2.9–3.05 ✓ |
| 门洞 | 2.20 高 × 1.45 宽 | ✓ |
| 门楣 | 2.27m | ✓ |
| 窗 | 1.15 × 0.90m | ✓ |
| 柱径 | 0.26–0.30m（门楼柱 ≤0.34） | 门楼 0.46 偏粗 → 改 0.30 |
| 檐口出挑 | 0.9–1.1m | 0.9 ✓ |
| 屋顶举折 | 26–28°（rise:half-run ≈ 1:2.2） | 约 1:2 ✓ |
| 正脊 | 0.18–0.24m | 0.2 ✓ |
| 脊端/翘角 | 0.35–0.42m，四角金端头 | ✓ |
| 门楼总高 | **6.0–6.4m** | 6.11 ✓ |
| 山门总高 | **7.0m**（柱 3.9 + 枋 + 檐） | 约 6.8 |
| 村舍 | 单层 3.0m，双坡屋顶 1.7m 高 | ✓ |
| 建筑群间距 | 6–9m，让檐口互相遮挡出层次 | — |
| 屋面贴图 | 瓦纹平铺 **0.9m/循环**，檐口暗一档 `#292522` | — |

**关键**：建筑要"3D"就得让人看见檐口厚度和屋脊高光——现在门楼/房子都在 6–15m 外，只有降低相机俯角后才会进画（§3）。

---

## 9. HUD 与中文排版

### 9.1 字号（设计值 1920×1080；960 屏即一半）

| 元素 | 现 | 目标 |
|---|---|---|
| 角色名 | 38 | **44** |
| 血/内力气条文字 | 25（压在条内） | **30，移到条上方 4px** |
| 气条高度 | 14 / 10 | **18 / 12** |
| 任务追踪 | 28 | **32**，行距 44 |
| 对话名 | 42 | **44** |
| 对话正文 | 44 | **46**，行距 14 |
| 菜单字 | 58（占位字） | **64**（换 icon 后给 76px icon） |
| 交谈按钮 | 42 | **44** |
| toast | 40 | 40 ✓ |

### 9.2 质感与布局

- 面板：`alpha 0.68 → 0.78`、金边 `3px → 2px`、圆角 `18 → 14`、内边距 18–20。
- 头像：108 → **120px** + 2px 金边；资源必须存在（当前 `res://docs/ref-characters-v3/shenyan_portrait_v2.png` 在快照里缺失 → 黑框）。加载前 `ResourceLoader.exists()` 兜底，回退到 v2 `shenyan_preview_v2.jpg` 裁切。
- 行/图/存/菜：改用 `assets/icons` 或与右侧技能钮同款"金边圆瓷 + 笔画"，**不要**圆底白字占位。
- 交谈钮：192 → **184px**、金边 2px、字 44、加 1px 内阴影；与圆形技能钮区分"主动作"。
- 摇杆：外径 300 → **280**，填充 alpha `0.55 → 0.35`，环 alpha 0.5。
- 安全区：顶部 `offset_top = 0 → 24`（圆角/刘海）。
- 对话框（dialogue_panel）：高 **172**、底边 **56**、圆角 16、底 `#241F1A` α0.90、金边 1.5px α0.75；名 `#D8B77A`，正文 `#F2ECE0`，outline 3px；▼ 放大到 **20px**，放 (right-40, bottom-24)。
- 中文排版规则：正文每行 ≤26 字、名字与正文间距 ≥12px、标点不顶头、正文左缩进 8px、`outline_size` 不超过 **3**（现在 3–8，屏上会糊）。
- 姓名板（Label3D）：`pixel_size 0.0046 → 0.0042`，`font_size 40`，位置 `height+0.30`，加半透明底板（0.65 黑，圆角 6，padding 6×2），否则压草不可读。

---

## 10. 2.5D 人物规范（核心）

### 10.1 Sprite3D 参数（沈砚 1.70m）

素材：`docs/ref-characters-v2/<char>_v2_<anim>_<dir>_<frame>.png`，画布 **420×500**，脚底锚点 **(210,476)**（以 `characters_v2.json` 为准）。

```gdscript
var s := Sprite3D.new()
s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # 只绕 Y 转，不随镜头俯仰躺倒
s.shaded = false                                  # 保留手绘明暗，不被 3D 光冲灰
s.double_sided = false                            # FIXED_Y 常朝镜头，省一遍填充
s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
s.render_priority = 2                             # 玩家 2 / NPC、道具 1
s.pixel_size = 0.00386                            # = 1.70m / 440px（立绘可见身高）
s.centered = true
s.offset = Vector2(0.0, 226.0)                    # (锚点-画布中心)px = (476-250)
```

换算核对：四边形 **1.621m 宽 × 1.930m 高**；脚底像素正好落在 y=0；头顶余 24px 透明（0.093m）。
其他身高：`pixel_size = 身高m / 作者身高px`（林照晚 1.63/422 = 0.003863），**不要**用节点缩放去改身高（会连影子宽度一起放大）。

### 10.2 8 方向映射表（相机 yaw 固定 0，+Z=朝镜头/屏下，+X=屏右）

```gdscript
# v = 世界移动方向 (x,z)，归一化
var idx := wrapi(int(round(atan2(v.x, v.z) / (PI * 0.25))), 0, 8)
const DIRS := ["down","downright","right","upright",
               "up","upleft","left","downleft"]
```

| idx | dir | 移动向量 (x,z) | 角度 | 素材后缀 |
|---|---|---|---|---|
| 0 | down | (0,+1) | 0° | `<char>_v2_<anim>_down_<f>` |
| 1 | downright | (+.707,+.707) | 45° | `_downright_` |
| 2 | right | (+1,0) | 90° | `_right_` |
| 3 | upright | (+.707,-.707) | 135° | `_upright_` |
| 4 | up | (0,-1) | 180° | `_up_` |
| 5 | upleft | (-.707,-.707) | 225° | `_upleft_` |
| 6 | left | (-1,0) | 270° | `_left_` |
| 7 | downleft | (-.707,+.707) | 315° | `_downleft_` |

规则：
- 8 个方向**各有素材，禁止运行时镜像**：不用 `flip_h`、不用负 `scale`、不用"right 帧翻面当 left"。
- 斜向 idle 素材本身就是该方向的 walk 第 1 帧（`characters_v2.json` 已说明），直接读 `_idle_<斜向>_0.png`。
- 方向切换加 **60–80ms 迟滞**（避免斜向抖动时来回翻帧）。

### 10.3 动画

- walk 帧序 **0-1-2-1**（`WALK_ORDER = [0,1,2,1]`），`FRAME_TIME = 0.12s`（≈8.3fps）。
- 移速 **1.9–2.1 m/s**（现 2.45 偏跑）；步幅约 0.9m，与帧率匹配。
- idle：单帧 + 呼吸（竖向 1.5% 缩放，周期 2.4s，现有 `idle_breath.gd` 可复用，注意只缩 Y）。
- 停止时先播完当前帧再回 idle，不要硬切。

### 10.4 Blob shadow（影子不再用实时阴影）

| 参数 | 值 |
|---|---|
| 网格 | `QuadMesh 0.95 × 0.48 m`（≈0.56 × 0.28 身高） |
| 位置 | 本地 `(0, 0.018, 0)`，`rotation (-90,0,0)` |
| 贴图 | `BlobShadow.texture()`（代码生成，128×64，#12161E 径向）或 `shadow_blob_v2_*.png` |
| 颜色/透明 | `albedo Color(1,1,1,0.52)` |
| 材质 | unshaded / transparency alpha / cull disabled / depth_draw disabled |
| 不投影 | `cast_shadow = OFF` |
| 运动 | 跟随脚底；移动时略拉长（0.95→1.05，沿移动方向）、停下回 1.0 |

### 10.5 区域色温（统一人物与场景）

- 村口：`modulate = (1.00, 0.98, 0.96)`；竹林：`(0.96, 1.00, 0.99)`；幅度 **≤±4%**。
- 过场/战斗不改 sprite 贴图，只改 `modulate`（4 行代码，零开销）。
- 接地暗部：贴图脚底 8% 高度预乘 **0.86** 暗（美术侧做一次），运行时不要再叠。

### 10.6 代码迁移清单（现状 → 规范）

| # | 文件 | 改什么 |
|---|---|---|
| 1 | `sprite_sheet.gd` | `CHARACTERS` 路径改 `ref-characters-v2/`；`canvas 320×420→420×500`、`anchor 160,396→210,476`、`PIXEL_SIZE 0.00474→0.00386`；删掉 4 方向折叠表 `FACING_TO_CARDINAL`，改 8 方向直映 |
| 2 | `player.gd` | `_direction_from_vector` 换成 §10.2 公式；`FRAME_TIME 0.13→0.12`；`SPEED 2.45→2.0`；`sprite.double_sided=false` |
| 3 | `npc.gd` | 同一套朝向公式；姓名 Label3D `pixel_size 0.0042`、`height+0.30`、加底板 |
| 4 | `world_builder.gd` | 探索态禁用 `NPC_MODELS` 的 GLB 分支（world_builder.gd:916-924）；GLB 只留给战斗特写/图鉴 |
| 5 | 素材路径 | `docs/` 在导出时可能被排除 → 把 v2/v3 立绘复制到 `assets/characters/`，代码改引用；加载前 `ResourceLoader.exists()` 兜底，缺资源时不显示名字 Label（现在名字悬空就是这么来的） |
| 6 | 战斗 | `battle/v2` 立绘是 2D 图（812×1117 / 锚点 707,1086，朝右），战斗层用 Sprite2D/TextureRect，不进 3D billboard |

---

## 11. 画风参照（只描述，不下载素材）

1. **《八方旅人 / Octopath Traveler》（HD-2D）**
   手绘立绘 + 3D 布景 + 强暖点光（灯笼/窗棂）+ 冷雾远景；局部移轴景深。
   可量化：角色屏高 12–16%、雾化远景 40–60%、高光晕 1.2–1.5 倍、画面有 1 个 ≥3 倍角色高的竖向量体（塔/树/门）。
2. **《哈迪斯 / Hades》**
   固定 3/4 俯角（≈40°）、角色有描边 + 冷色轮廓光、地面低饱和、技能特效高饱和；UI 大圆角 + 金线。
   可量化：角色占屏 18–22%、影子是软 blob（不是硬实时影）、地面饱和度 ≈0.35–0.45。
3. **《仙剑客栈 / 大侠立志传》**
   中式市井 2.5D 高俯角；木色建筑 + 青绿地面 + 纸/木质感 UI；宋体标题。
   可量化：地面三色阶 `#6D7342/#B19D7D/#C9B492`、UI 面板深棕 α0.85 + 金边、门窗 2.2m 为人物 1.3 倍。

本项目取：①的冷雾 + 暖灯 + 远景带；②的 40° 俯角与 blob 影；③的配色与木质 UI。

---

## 12. 本项目现有素材：可直接复用

| 素材 | 用途 |
|---|---|
| `docs/ref-characters-v2/` 沈砚/林照晚 8 方向 idle+walk（420×500，锚点 210,476） | 主角/NPC 2.5D 立绘唯一来源 |
| `docs/ref-characters-v2/shadow_blob_v2_*.png`（256×128 / 512×256 / offset_br） | 人物/道具影子，配套参数见 §10.4 |
| `docs/ref-characters-v3/npc/` 周伯/明澄/厉横 8 向（420×500 与 460×540） | 村民 NPC；注意 canvas/anchor 与 v2 不同 |
| `assets/props/prop_*.png` + `_shadow_r4.png`（石灯/篱笆/木箱/路牌/井） | 地面装饰主力（像素锚点已写在 world_builder `PROPS`） |
| `assets/icons/icon_*_r4.png`（攻/守/药/剑技/敌方 3 种） | HUD 按钮图标，替换 行/图/存/菜 占位字 |
| `assets/fonts/shanhe_serif.otf`（思源宋体 SC） | 全部 UI 与 Label3D；字号按 §9.1 |
| `docs/scene_art_direction.md` 调色板/材质表 | 统一色彩基线（雾 `#DDE6EE`、瓦 `#25201D–#6E6661`、木 `#2D2221–#7F7570`） |
| `assets/glb/*.glb`（4 个角色模型） | 只用于战斗特写/图鉴，**不进探索态** |
| `building_factory.gd` 程序化建筑 | 保留（门 2.2m/层高 3.0m 已达标），按 §8 微调 |

**缺口**（需要补的）：
- 地面贴花（`ground_grass_tile` / `ground_dirt_tile` 需确认在 assets 里）
- 落叶/纸纹噪点（可由代码生成，`_make_cloud_texture` 同款思路）
- 暗角/颗粒 shader（新建 1 个 `shaders/post_fx.gdshader`，别再加水体 shader）

---

## 13. 验收清单（改完重新截图逐条打勾）

**相机**
- [ ] 角色屏高 17–20%，脚底线 58–62% 屏高
- [ ] 画面顶边能看到门楼/屋脊/檐角（≥1 处高于 3m 的构件）
- [ ] 中心 50%×55% 无遮挡

**色彩**
- [ ] 地面中心采样亮度 ≤ `#E2DCC4`（不再接近白）
- [ ] 画面最暗处 ≤ `#3A3228`（有暗锚点）
- [ ] 中心/暗部对比 ≥25%
- [ ] 远景 25–40m 有 ≥2 层剪影 + 雾，不是一块白

**人物**
- [ ] `FIXED_Y` billboard，人物始终正面朝镜头、脚贴地
- [ ] 影子是软 blob（0.95×0.48，#12161E α0.52），不是硬实时影
- [ ] 8 方向各有素材，无镜像、无"侧面帧当斜向"
- [ ] walk 0-1-2-1，步频与 2.0m/s 匹配；idle 有呼吸

**HUD**
- [ ] 对话框屏上正文 ≥22px、行距 ≥7px、名字与正文 ≥6px
- [ ] 血/内力文字在条外，18px 条高，读得清
- [ ] 头像非黑块；菜单按钮有图标不是白字占位
- [ ] 顶部安全区 24px，圆角屏不切图标

**性能（Mobile 30fps 预算）**
- [ ] draw call ≤ 120；阴影 caster ≤ 20；三角面 ≤ 150k
- [ ] glow 1 pass、无 SSAO/SSR/SDFGI/体积雾
- [ ] 草/竹/落叶每类 ≤1 个 MultiMesh 批次

---

## 附：关键数值速查

```
相机  俯角38° FOV38 距离11.8m offset(0,7.27,9.30) look1.15 smooth6.0
环境  FILMIC exp0.82 white8.0 amb0.34/0.45 sat1.00 con1.10
雾    DEPTH 16–58 density0.85 #DCE6EE aerial0.45 height0.9/0.5
主光  (-46,-132) #FFE8C6 1.18 shadow42m blur1.6 bias0.05 nb1.5
人物  pixel_size0.00386 420×500 anchor(210,476) offset(0,226)px
影子  0.95×0.48 y0.018 #12161E α0.52 unshaded no-cast
动画  walk 0-1-2-1 @0.12s  speed2.0m/s
建筑  门2.2 层高3.0 檐挑0.9 举折26–28° 门楼6.2 山门7.0
HUD   名牌44 正文46 条高18 alpha0.78 金边2px 安全区24
```
