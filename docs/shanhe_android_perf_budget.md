# 《山河剑行》HD-2.5D（Godot 4.7.2）安卓中端机性能预算与测量方法

- 版本：v0.1，2026-11-10 01:40（UTC+8，北京时间）
- 作者：性能调优（Perf Tuner），只读审阅，未修改、未提交、未安装任何东西
- 审阅窗口：01:34–01:42（UTC+8）。Codex 在这段时间内正在写这个工程，状态会变
- 适用：`/workspace/godogen-shanhe` 当前这一轮的竖切片（村庄 + 山门、探索、对话、回合制战斗）

> **标注约定**
> - 【项目事实】：本次在仓库里亲眼看到的内容，附路径和行号
> - 【文档事实】：来自 Godot 官方文档（4.7 stable），附链接
> - 【建议预算（待实测）】：起始数值，用来在真机上校准。**本文没有任何真机测量结果，也不声称任何优化已经验证有效。**
> - 【推断】：根据现状推出来的判断，还没被证实

---

## 0. 结论速览

| 项 | 建议 |
|---|---|
| 安卓渲染器 | **Mobile**（`rendering/renderer/rendering_method.mobile="mobile"`）。安卓不要用 Forward+。PC 截图也建议用 Mobile 跑一遍，避免两边画面不一致 |
| 默认档 | **30 fps 稳定**（帧时间 33.3 ms），3D 内部分辨率缩放 0.75 |
| 高档 | 60 fps（16.6 ms），只给 Adreno 7xx / 天玑 8xxx 这类机型，必须实测达标才开 |
| SSAO | Mobile 渲染器**不支持**，改成烘焙 AO、顶点色 AO 或贴脚底的圆形影子 |
| 体积雾 / SSR / SDFGI / SSIL | Mobile 都**不支持**，全部关掉。只用深度雾 + 高度雾，再加少量雾片 |
| 默认档上限 | DrawCall ≤ 300，Primitives ≤ 600k（引擎计数，含阴影和预深度），纹理显存 ≤ 256 MB，进程 PSS ≤ 1.0 GB，安装包 ≤ 150 MB |
| 纹理 | 打开 `import_etc2_astc`。3D 环境贴图用 VRAM Compressed，主要贴图选 High Quality（ASTC 4×4）。角色立绘和精灵用 Lossless，或单独评估 ASTC |

---

## 1. 项目现状审阅（只读）

### 1.1 关键发现：Godot 工程文件还没生成

【项目事实】审阅时间是 2026-11-10 01:34–01:36（UTC+8）。当时 `/workspace/godogen-shanhe` 里**没有** `project.godot`、`export_presets.cfg`，也没有任何 `.tscn`、`.tres`、`.gdshader` 或 `.import` 文件：

```
$ ls /workspace/godogen-shanhe
AGENTS.md  BRIEF.md  codex-run1.log  docs  godot-gdscript.md
$ rg --files -g project.godot /workspace /home   -> 无结果
$ git log --oneline
7625281 brief and refs
7f4ddea godogen godot-gdscript scaffold
```

同一时间，Codex 进程正在跑 brief（`codex -p max exec -s workspace-write ... Read AGENTS.md and BRIEF.md and execute the brief`，01:33 启动）。所以下面这些要求的检查项**都还审阅不了**，标为“未审阅项目”：

| 检查项 | 状态 |
|---|---|
| project.godot 中的 `rendering/renderer/rendering_method` 和 `.mobile` 覆盖 | 未审阅（文件不存在） |
| `.import` 的压缩模式、ETC2/ASTC、mipmaps | 未审阅（不存在，而且 `.gitignore` 第 9 行忽略了 `*.import`，见下） |
| WorldEnvironment / Environment `.tres` 中 SSAO/SSIL/SDFGI/glow/fog/volumetric | 未审阅 |
| 光源阴影设置 | 未审阅 |
| 植被 / 草 `.gdshader` | 未审阅 |
| MultiMesh 使用 | 未审阅 |
| export_presets.cfg 安卓设置 | 未审阅 |

工程生成后，可以用第 9 节的 `rg` 命令清单重新审阅一遍（也是只读）。

### 1.2 已能看到的、会影响性能的事实

| # | 【项目事实】 | 证据 | 性能含义（【推断】） |
|---|---|---|---|
| F1 | Brief 要求 “soft shadows, **SSAO/glow**, water, mist, wind-swayed bamboo”，并且 “Android later” | `BRIEF.md` 第 3、6 行 | 按文档，SSAO 在 Mobile 渲染器上不支持（见第 3 节）。按 Forward+ 调出来的画面迁到安卓时会丢效果，或者被迫在安卓上用 Forward+ |
| F2 | 角色用 “HD billboard sprites (Sprite3D, pixel-perfect, foot-anchored, with shadow)” | `BRIEF.md` 第 6 行 | 半透明精灵投影、alpha 测试和 overdraw 都有成本。“像素完美”和 3D 分辨率缩放（<1.0）有冲突 |
| F3 | 目标 1920×1080 全屏横屏 | `BRIEF.md` 第 3 行 | 中端机全分辨率跑 3D 后处理的压力很大，建议做 3D 内部分辨率缩放 |
| F4 | 工程指南说 “MultiMeshInstance3D + GLB loses the mesh on pack/save; use individual instances” | `godot-gdscript.md`（codex-run1.log 第 132 行引用了这一句） | **最大的 DrawCall 风险**：Codex 很可能把竹子和草做成上百个独立 MeshInstance3D。正确做法是 MultiMesh 配**程序化 ArrayMesh**（不受这条 GLB 限制） |
| F5 | 工程指南说 “never `create_trimesh_shape()`/`create_convex_shape()` on imported meshes (drops to <1 FPS)” | `godot-gdscript.md` | 碰撞要坚持用基本形状 |
| F6 | 工程指南说 “`SurfaceTool.generate_normals()` is required … (or with `CULL_DISABLED` …)” | `godot-gdscript.md` | 别用 `cull_disabled` 偷懒，双面渲染会让片元成本翻倍 |
| F7 | 美术参考图：48 张 PNG，磁盘 10.6 MB。如果全部按 RGBA8 未压缩载入，约 74.6 MiB。仅 40 帧行走/待机帧就约 21.1 MiB | `docs/ref-characters/*.png`（本次用 PIL 统计） | 精灵帧如果 Lossless 载入，主要吃纹理内存，但还在预算内。注意不要同时载入 turnaround、raw 这类非运行时资源 |
| F8 | 大图：`shenyan_spritesheet.png` 1280×2100（RGBA8 约 10.3 MiB）、`linzhaowan_spritesheet.png` 1360×2100（约 10.9 MiB）、`*_turnaround.png` 1900×1250（约 9.1 MiB）、立绘约 1000×1050（约 3.2–4.1 MiB） | 同上 | 精灵表和单帧 PNG 只能二选一进包。turnaround、preview、raw 不能进 `assets/` |
| F9 | `docs/ref-characters/raw/` 有 7.2 MB 的 jpg 原始参考图 | `du -sh` | 如果被复制到 `assets/` 或没被排除导出，包体会白白变大 |
| F10 | `.gitignore` 忽略 `*.import`、`.godot`、`assets`、`screenshots` | `.gitignore` | `.import` 不进 git，压缩设置只存在于本地。**`assets` 整个目录也被忽略**，git 里审阅不到导入设置，必须直接在机器上看文件 |
| F11 | 本机**没有 GPU**（`AGENTS.md`：“CPU onnxruntime; no GPU on this machine”）。01:34 时 Codex 的环境检查里 `java: command not found`，也没有 export templates（codex-run1.log 约第 1604–1615 行）。**01:38 左右，另一个 agent 装好了安卓导出工具链**：`~/.local/share/godot/export_templates/4.7.2.stable/`、`~/apps/jdk17`、`~/apps/android-sdk`（build-tools 35.0.1、platform-tools 带 adb），并用空工程导出了一个 **27 MB（28,246,415 字节）** 的 debug APK：`/tmp/godot-android-test/test.apk`。这个空工程的 `project.godot` 第 19 行是 `renderer/rendering_method="mobile"` | `docs/godot-android-export-notes.md`；本次 `ls` 核对了路径；`/tmp/godot-android-test/project.godot` | 现在能打包，但**本机仍然测不了任何性能数字**（没有 GPU、没有真机），软件 Vulkan 下的帧率没有参考价值，真机数据只能靠安卓设备 + adb。**空工程 APK 约 27 MB 是包体的基线**（单 arm64），游戏内容的预算要在这之上算 |
| F14 | 审阅期间 `BRIEF.md` 被追加了一段 “Update (from design team)”，未提交：要求加 `export_presets.cfg`（Gradle 关、arm64-v8a、横屏），设 `textures/vram_compression/import_etc2_astc=true`，导出 `build/shanhe-debug.apk`。导出笔记说缺这个设置时导出会报 “ETC2/ASTC texture compression is required for Android export” | `git diff BRIEF.md`（第 22–26 行）；`docs/godot-android-export-notes.md` 的 “Project requirements” 一节 | 和本文第 6 节的建议一致。Brief 更新里**没有提渲染器选择**，SSAO 的冲突（F1）依然存在 |
| F12 | 场景构图：人物高约 0.07–0.08H，竹/树冠幅超过人高 5 倍，用作画框，左右两侧是密林 | `docs/scene-layout-notes.md` §1、§3 | 两侧大面积竹叶，再加前景草，叠在一起是**overdraw 热点**。前景“半透明 40%”遮挡会再加一层混合 |
| F13 | 旧版 `/workspace/shanhe-delivery/` 是原生 Android（Gradle）APK，不是 Godot | `BUILD_REPORT.md` | 旧包的性能和包体数据不能拿来当 Godot 版的参考 |

---

## 2. 目标机型与帧率

### 2.1 目标机型（中端安卓）

| 档 | 代表 SoC / GPU | 内存约束 |
|---|---|---|
| 基准机（默认档必须达标） | 骁龙 778G / 7 Gen 1（Adreno 642L / 644），天玑 1080 / 7050（Mali-G68 MC4） | 设备 6–8 GB，**游戏可用约 3–4 GB** |
| 高档参考 | 骁龙 7+ Gen 2 / 7+ Gen 3（Adreno 725/732），天玑 8100/8200（Mali-G610 MC6） | 8–12 GB |
| 底线机（低档能跑就行） | 骁龙 695（Adreno 619），Helio G99（Mali-G57 MC2） | 4–6 GB |

至少采购 3 台：**1 台 Adreno 642L 或 644、1 台 Mali-G68 或 G610、1 台底线机**。Adreno 和 Mali 的瓶颈差别很大，比如 Mali 对 alpha 测试和带宽更敏感（【推断】，需实测）。

### 2.2 帧率与帧时间预算【建议预算（待实测）】

| 档 | 目标 | 帧时间 | 主线程 CPU（脚本 + 物理 + 场景） | 渲染线程 CPU | GPU | 余量 |
|---|---|---|---|---|---|---|
| 低 | 30 fps | 33.3 ms | ≤ 10 ms | ≤ 8 ms | ≤ 24 ms | ≥ 25% |
| **默认（中）** | **30 fps 稳定** | **33.3 ms** | **≤ 12 ms**（脚本 ≤ 4、物理 ≤ 2） | **≤ 8 ms** | **≤ 24 ms** | 留 25–30% 给温控降频 |
| 高 | 60 fps | 16.6 ms | ≤ 7 ms | ≤ 5 ms | ≤ 12 ms | ≥ 25% |

- GPU 预算按“不封顶时测出的 GPU 时间”来定：开 30 fps 上限后，看到的总是 33.3 ms，余量看不出来。
- 回合制战斗场景可以和探索场景用同一套预算。战斗演出时粒子、辉光增加，**要单独测**。
- 帧率上限：默认档 `Engine.max_fps = 30` 或 `application/run/max_fps=30`。另外，【文档事实】Godot 安卓默认开着 Swappy 帧节奏（`display/window/frame_pacing/android/enable_frame_pacing=true`，默认 `swappy_mode=2` 是 auto_fps_auto_pipeline）。文档提醒：auto 模式“will often downgrade the max FPS until it finds a value that can be maintained”。**测试时要固定 `swappy_mode=0`（pipeline_forced_on）加显式 `max_fps`**，否则 60 档会被悄悄降成 30，测量就失真了。链接：https://docs.godotengine.org/en/stable/classes/class_projectsettings.html

### 2.3 温控稳定性要求【建议预算（待实测）】

- 25 °C 室温，不接充电，亮度 50%，飞行模式。连续跑固定镜头路径 **30 分钟**，测试脚本见第 7 节。
- 通过标准：
  - 第 25–30 分钟的平均 fps ≥ 第 0–5 分钟的 **95%**；默认档要 ≥ 29.0 fps
  - 1% low ≥ 25 fps（默认档），≥ 50 fps（高档）
  - `dumpsys thermalservice` 状态 ≤ 2（MODERATE），30 分钟内不出现 ≥ 3（SEVERE）
  - 电池温度 ≤ 42 °C（`dumpsys battery` 的 temperature ≤ 420）
  - 30 分钟内 PSS 增长 ≤ 50 MB（防泄漏）
- 高档 60 fps 如果在 20 分钟后跌破 55 fps，就自动或建议降到默认档。

---

## 3. Forward+ vs Mobile 渲染器选择

### 3.1 文档事实（Godot 4.7 “Overview of renderers”）

链接：https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html

| 特性 | Mobile | Forward+ | 本项目相关性 |
|---|---|---|---|
| 移动端定位 | “✔️ Yes (high-end)” | “⚠️ Supported, but **poorly optimized**. Use Mobile or Compatibility instead.” | 决定性 |
| 渲染成本 | “Medium base cost, and medium scaling cost” | “Highest base cost, and low scaling cost” | |
| 光照 | Forward single-pass；**每个网格最多 8 个 Omni + 8 个 Spot，每个视图 256 个**（“These limits currently cannot be changed”，见 lights_and_shadows 页） | Clustered，每簇 512 个 | 灯笼和火把要控制数量 |
| 深度/高度雾 | ✔️ | ✔️ | 用这个 |
| **体积雾** | ❌ | ✔️ | 山门雾气不能靠它 |
| **SSAO** | ❌ **Not supported** | ✔️ | **和 Brief 冲突（F1）** |
| SSR | ❌ | ✔️ | 水面反射不能靠它 |
| SSIL / SDFGI / VoxelGI | ❌ | ✔️ | |
| LightmapGI | ✔️ | ✔️ | 可以用来烘焙 AO 和间接光 |
| ReflectionProbe | 每网格 8 个 | 不限 | |
| Glow | ✔️ | ✔️ | 能用 |
| DirectionalLight 的 PCSS | ❌ | ✔️ | 方向光软阴影只能用 PCF 过滤档 |
| TAA / FSR2 | ❌ | ✔️ | Mobile 只能用 MSAA、FXAA、SMAA |
| FSR1 缩放 | ProjectSettings 文档：“FSR is only effective when using the Forward+ rendering method, not Mobile … will fall back to bilinear” | ✔️ | Mobile 下 3D 缩放实际是双线性 |
| 屏幕纹理 / 深度纹理 | ✔️ | ✔️ | 水 shader 能读，但有成本 |
| 颜色精度 | RGB10A2（低精度） | RGBA16F | 辉光和雾的过渡可能出色带，Mobile 支持 debanding |
| Sub-surface scattering | ❌ | ✔️ | |

另外：
- 【文档事实】Compatibility 渲染器表里写着支持 SSAO，但它没有 Glow 的同款实现，也没有高质量 ASTC（文档：“High-quality VRAM texture compression is only supported in the Forward+ and Mobile renderers”）。
- 【文档事实】`rendering/renderer/rendering_method.mobile` 的默认值就是 `"mobile"`，表示“Override for rendering_method on mobile devices”。也就是说，只要 Codex 没去改这个覆盖项，安卓上本来就会跑 Mobile。**真正的风险是 PC 用 Forward+ 调出来的画面（含 SSAO）到了安卓会变样。**

### 3.2 推荐

**安卓用 Mobile 渲染器，不用 Forward+。** 理由：
1. 官方文档明确说 Forward+ 在移动端“poorly optimized”，基础成本最高。
2. 本项目视角固定、场景规模小（村庄 + 山门），用不上 Forward+ 低“缩放成本”的优势。
3. Forward+ 独有的特性（SSAO、体积雾、SSR、SDFGI）在中端机上本来也开不起。

**执行建议：**
- `project.godot` 里写 `rendering/renderer/rendering_method="mobile"`，**PC 端也用 Mobile**；或者至少每次截图前用 `--rendering-method mobile` 跑一遍做对比。这样美术调出来的效果就是安卓上的效果。如果要保留 PC 用 Forward+，必须明确把 `.mobile="mobile"` 写进去，并接受两端画面有差异。
- SSAO 的替代：
  - 建筑和岩石：烘焙 AO 到顶点色或贴图（程序化网格可以在生成时算凹角 AO），或者用 LightmapGI 烘焙
  - 角色：贴地圆形影子（Decal，或一个 alpha 渐变 quad）
- 【不确定】Godot 后续版本可能会给 Mobile 加 SSAO。本文以 4.7 stable 文档为准，换版本前请重新核对上面的链接。

---

## 4. 画质分档开关表

分档实现方式：一个运行时 `QualitySettings` autoload 根据档位写入 Environment、Light 和 Viewport 属性。属性名来自 Godot 类参考，**数值是建议起点（待实测）**。

### 4.1 全局 / 视口

| 项（属性 / 设置名） | 低 | 中（默认） | 高 |
|---|---|---|---|
| 帧率 `Engine.max_fps` | 30 | 30 | 60 |
| 3D 缩放 `rendering/scaling_3d/scale`（运行时用 `Viewport.scaling_3d_scale`） | 0.6 | 0.75 | 0.9–1.0 |
| `rendering/scaling_3d/mode` | Bilinear（Mobile 下 FSR 也会退回 bilinear） | 同左 | 同左 |
| MSAA `Viewport.msaa_3d`（`rendering/anti_aliasing/quality/msaa_3d`） | 关 | 2× | 2×（4× 要实测，Mali 带宽敏感） |
| 屏幕空间 AA `screen_space_aa` | 关 | 关（有 MSAA） | FXAA 或关 |
| 各向异性 `rendering/textures/default_filters/anisotropic_filtering_level` | 0 | 1（2×） | 2（4×，默认） |
| Debanding `rendering/anti_aliasing/quality/use_debanding` | 关 | 开（Mobile 支持，治 RGB10A2 色带） | 开 |
| 遮挡剔除 `rendering/occlusion_culling/use_occlusion_culling` | 视场景而定，2.5D 俯视下收益可能很小（【推断】） | 同左 | 同左 |
| UI | 一直按原生分辨率（2D 不受 3D 缩放影响） | | |

> 像素完美精灵（F2）和 3D 缩放 < 1.0 会冲突：精灵会被重采样。两个选项：(a) 接受轻微模糊，(b) 只在高档用 1.0。【建议】默认档先用 0.75，在真机上看清晰度后再决定。

### 4.2 SSAO / 间接光

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| `Environment.ssao_enabled` | false（Mobile 不支持） | false | false |
| `ssil_enabled` / `sdfgi_enabled` / `ssr_enabled` | false | false | false |
| 替代方案 | 顶点色 AO | 顶点色 AO + 角色脚底影 | + LightmapGI 烘焙（如果流程允许） |

### 4.3 辉光（Environment）

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| `glow_enabled` | false | true | true |
| 启用的 `glow_levels/1..7` | — | 2 级（例如 3、4） | 3 级（例如 2、3、4） |
| `glow_hdr_threshold` | — | ≥ 1.0（只让灯笼、剑光、水面高光发光） | 0.9 |
| `rendering/environment/glow/upscale_mode.mobile` | — | 0（Linear） | 0 或 1（Bicubic），1 更贵 |

### 4.4 阴影

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| 方向光 `shadow_enabled` | true（或 false 并改用角色圆影） | true | true |
| `directional_shadow_mode` | `SHADOW_ORTHOGONAL` | `SHADOW_PARALLEL_2_SPLITS` | `SHADOW_PARALLEL_2_SPLITS`（俯视 2.5D 下 4 分割收益低，【推断】） |
| `directional_shadow_max_distance` | 25 m | 40 m | 60 m（按镜头视锥实际可见深度收紧，越小越清晰越省） |
| `rendering/lights_and_shadows/directional_shadow/size.mobile`（文档默认 2048） | 1024 | 2048 | 2048（4096 只在实测通过后才开） |
| `.../directional_shadow/soft_shadow_filter_quality.mobile`（文档默认 0 = Hard） | 0 Hard | 1 Soft Very Low | 2 Soft Low |
| `directional_shadow/16_bits` | true | true | true |
| Omni/Spot 阴影（`positional_shadow/atlas_size.mobile`） | 关 | 关 | 最多 1 个，atlas 1024–2048 |
| 草和小植被 `GeometryInstance3D.cast_shadow` | OFF | OFF | OFF |
| 竹子投影 | OFF | 只有前景大丛 ON | ON |
| 角色 Sprite3D 投影 | 圆影 | 圆影 | 实时投影（需要 alpha scissor 或 opaque prepass，【推断】需验证投影形状正确） |
| `rendering/lights_and_shadows/tighter_shadow_caster_culling` | true | true | true |

光源数：每个网格受到的 Omni + Spot 光照，默认档 ≤ 4 个（硬上限是 8+8，见第 3 节）。整个视图里动态点光默认档 ≤ 8 个。

### 4.5 雾

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| `Environment.fog_enabled` | true | true | true |
| `fog_mode` | 深度雾（`FOG_MODE_DEPTH`，配 `fog_depth_begin/end`）或指数雾 | 指数 + 高度雾（`fog_height`、`fog_height_density`） | 同中 |
| `volumetric_fog_enabled` | false（Mobile 不支持） | false | false |
| 雾片 / 山岚卡片（半透明 quad + 噪声 shader） | 0 | ≤ 4 片，每片屏占比 < 15% | ≤ 8 片 |
| 规则 | 雾片不能叠成多层全屏，否则 overdraw 失控。雾片 shader 不要采样 `SCREEN_TEXTURE` | | |

### 4.6 植被 shader 与实例

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| 渲染方式 | **MultiMeshInstance3D + 程序化 ArrayMesh**（不用 GLB，见 F4），按约 16 m 分块，方便视锥剔除 | 同左 | 同左 |
| 透明方式 | 竹竿：不透明。叶片和草：**alpha scissor**（`BaseMaterial3D.transparency = TRANSPARENCY_ALPHA_SCISSOR`，或在 shader 写 `ALPHA_SCISSOR_THRESHOLD`），**禁止 alpha blend** | 同左 | 同左；远景可以用 alpha-to-coverage + MSAA（需实测） |
| 叶片形状 | 尽量做成贴合轮廓的多边形，减少镂空像素（discard 在 TBDR 上会让 early-Z 失效，【推断】Mali 上尤其明显） | | |
| 风动 | 在顶点 shader 里用 `sin(TIME + 世界坐标相位) * 高度权重`。**顶点阶段不采样纹理**。低档关闭或减幅 | 开 | 开，加二级摆动 |
| 可视距离 `visibility_range_end` / `visibility_range_end_margin` / `visibility_range_fade_mode` | 草 15 m | 草 25 m | 草 35 m |
| 草实例上限（视野内） | 1,500 | 4,000 | 8,000 |
| 竹竿实例上限（视野内） | 60 | 120 | 200 |
| 每根草三角面 | ≤ 4 | ≤ 6 | ≤ 8 |
| 竹 LOD | 2 级（近处模型 / 远处卡片） | 3 级 | 3 级 |
| 前景遮挡淡出（`scene-layout-notes.md` §3 要求的 40%） | 换成**抖动透明**（dither discard），不用 alpha blend | 同左 | 可以 alpha blend，但只用于遮挡主角的那 1–2 个物体 |
| `cull_mode` | 双面草片可以 `cull_disabled`；不要给实体网格开 | | |

### 4.7 水面

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| 实现 | 不透明，顶点色加 UV 滚动法线 | 加 `DEPTH_TEXTURE` 读岸边泡沫 | 加 `SCREEN_TEXTURE` 折射（需实测成本） |
| 反射 | 无，或用一张预烘焙的天空 cubemap | 同低 | ReflectionProbe（UPDATE_ONCE） |

---

## 5. 预算上限【建议预算（待实测）】

口径：`Performance` 单例在 debug 构建、默认档、1920×1080 设备、3D 缩放 0.75 下的数值。各指标的定义见第 7 节。**这些都是起步预算，不是测量结果。**

| 指标 | 低 | **中（默认）** | 高 | 说明 |
|---|---|---|---|---|
| 每帧 DrawCall `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | ≤ 200 | **≤ 300** | ≤ 450 | 含阴影 pass。不含阴影的主 pass 建议 ≤ 180 |
| 每帧可见对象 `RENDER_TOTAL_OBJECTS_IN_FRAME` | ≤ 150 | **≤ 250** | ≤ 400 | |
| `RENDER_TOTAL_PRIMITIVES_IN_FRAME` | ≤ 350k | **≤ 600k** | ≤ 1.0M | 文档：这个数包含深度预 pass 和阴影 pass，“typically double or triple”。对应场景里唯一可见三角面约为默认档 ≤ 200–250k |
| 单个网格面数 | 角色 billboard 2 tris；建筑 ≤ 5k；大石 ≤ 2k；竹竿 ≤ 200 | | | |
| 同屏唯一材质 | ≤ 20 | **≤ 30** | ≤ 40 | |
| 自定义 `.gdshader` 文件数 | | **≤ 10**（水、雾、竹、草、地面、精灵、天空、UI 特效……） | | 避免同一个 shader 复制出多份只改常量。改用 uniform 加 instance uniform |
| 游戏中途的管线编译 `PIPELINE_COMPILATIONS_DRAW` | 预热后 **= 0** | | | 第一次进场景可以有 `..._SURFACE`/`..._MESH`，但进入战斗、切换场景时不应该出现 DRAW 编译 |
| 纹理内存 `RENDER_TEXTURE_MEM_USED` | ≤ 160 MB | **≤ 256 MB** | ≤ 384 MB | |
| 显存合计 `RENDER_VIDEO_MEM_USED` | ≤ 256 MB | **≤ 400 MB** | ≤ 550 MB | 包含 render buffer（4.7 文档说 VIDEO 大于 TEXTURE + BUFFER 之和） |
| 进程总内存（`adb shell dumpsys meminfo <pkg>` 的 TOTAL PSS） | ≤ 750 MB | **≤ 1.0 GB** | ≤ 1.3 GB | 硬红线 1.2 GB（默认档）。3–4 GB 可用内存的设备，后台切回时容易被杀 |
| 安装包（APK，arm64-v8a 单架构） | | **≤ 150 MB**；竖切片阶段 ≤ 80 MB（空工程基线约 27 MB，见 F11，所以内容 ≤ 53 MB） | | AAB 上架前请核对 Google Play 当前对 base module 的大小限制【不确定，需查 Play 文档】 |
| 冷启动到标题画面 | | **≤ 5 s**（基准机） | | 用 `adb shell am start -W` 的 TotalTime 加脚本打点 |
| 探索场景加载 | | **≤ 3 s** | | |
| 探索到战斗切换 | | **≤ 1.0 s**，不得掉帧超过 100 ms | | |
| 单帧尖刺 | | 正常游玩时每 5 分钟出现 > 100 ms 的帧 ≤ 1 次（加载时不算） | | |

---

## 6. 纹理压缩（安卓）

### 6.1 文档事实

链接：https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html 和 ProjectSettings 类参考。

- `rendering/textures/vram_compression/import_etc2_astc`（默认 false）：开启后，“ETC2 for lower quality textures and normal maps and ASTC for high quality textures (in 4×4 block size)”。改了以后**不会影响已经导入过的纹理**，需要删掉 `.godot/imported/` 重新导入。（这是写操作，交给 Codex 做，本文不执行。）
- `Compress > High Quality`：开启时，移动端用 **ASTC**；不开时移动端用 **ETC2**。文档：“High-quality VRAM texture compression is only supported in the Forward+ and Mobile renderers”。
- `Compress > Normal Map`：默认 Detect，检测到用作法线贴图就改成 RGTC，只保留 RG 两个通道（内置材质会忽略 B 通道，自定义 shader 需要自己重建 Z）。Godot 要求 OpenGL 风格（Y+）法线，DirectX 风格的需要勾 `Normal Map Invert Y`。
- `Detect 3D`：纹理第一次被 3D 使用时，自动改成 VRAM Compressed 并开启 mipmap。
- Mipmaps 会多用约 33% 内存。文档建议 3D 开、2D 一般不开。`Mipmaps > Limit` 目前“not implemented”。
- `Lossless` / `Lossy` 只省磁盘，**不省显存**。VRAM Compressed 才省显存。

### 6.2 建议【建议预算（待实测）】

| 纹理类别 | 压缩模式 | High Quality | Mipmaps | 尺寸上限（`Process > Size Limit`） |
|---|---|---|---|---|
| 3D 地面、岩石、建筑、竹叶图集 | VRAM Compressed | 主要地表和建筑开（ASTC 4×4，约 8 bpp）；次要的关（ETC2） | **开** | 1024；地面主贴图 2048 |
| 法线贴图（如果有） | VRAM Compressed，Normal Map = Enable | — | 开 | 1024 |
| 角色 Sprite3D 帧 / 精灵表 | **Lossless**（避免 ETC2 的 alpha 边缘块状伪影，配合 `Fix Alpha Border`）；内存超预算时再试 ASTC 4×4 HQ 并做肉眼对比 | — | 3D 缩放 < 1 或镜头会拉远：开；固定像素完美：关 | 单帧 ≤ 512；精灵表 ≤ 2048（现有 1280×2100 和 1360×2100 超过 2048，见 F8，建议重新打包成 ≤ 2048 的图集） |
| 对话立绘（2D UI） | Lossless 或 Lossy（只省磁盘） | — | 关 | 1024（现在约 1000×1050，可以接受） |
| UI 图标、九宫格 | Lossless | — | 关 | 按需 |
| 噪声和风场小贴图 | VRAM Compressed（单通道可以考虑 R8 未压缩） | — | 开 | 256 |
| HDR 天空 | 尽量换成程序化 Sky（`ProceduralSkyMaterial`），不用 HDR 贴图 | | | |

估算：现在 40 帧行走/待机图按 RGBA8 载入约 21 MiB，精灵表约 21 MiB，两者只能留一种。立绘 2 张加战斗图 2 张约 14 MiB。角色类合计 ≤ 40 MiB，在 256 MB 纹理预算内。**turnaround、preview、raw 不能进 assets**。

---

## 7. 测量方法

### 7.1 指标与工具

【文档事实】`Performance` 单例的枚举名已在 4.7 类参考核实：https://docs.godotengine.org/en/stable/classes/class_performance.html

| 指标 | 枚举名 | 备注（文档原意） |
|---|---|---|
| FPS | `Performance.TIME_FPS` | 每秒更新一次，只作参考 |
| 帧处理时间 | `Performance.TIME_PROCESS` | 单位秒 |
| 物理帧时间 | `Performance.TIME_PHYSICS_PROCESS` | 单位秒 |
| 静态内存 | `Performance.MEMORY_STATIC` / `MEMORY_STATIC_MAX` | **release 构建不可用** |
| 对象 / 节点 / 孤儿节点 | `OBJECT_COUNT` / `OBJECT_NODE_COUNT` / `OBJECT_ORPHAN_NODE_COUNT` | 孤儿节点只在 debug 构建可用 |
| 可见对象 | `RENDER_TOTAL_OBJECTS_IN_FRAME` | 不含被剔除的 |
| 图元 | `RENDER_TOTAL_PRIMITIVES_IN_FRAME` | 含深度预 pass 和阴影，通常是 2–3 倍 |
| DrawCall | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | |
| 显存 | `RENDER_VIDEO_MEM_USED` / `RENDER_TEXTURE_MEM_USED` / `RENDER_BUFFER_MEM_USED` | |
| 管线编译 | `PIPELINE_COMPILATIONS_CANVAS` / `_MESH` / `_SURFACE` / `_DRAW` / `_SPECIALIZATION` | `_DRAW` 对应游戏中的卡顿 |

精确 CPU/GPU 渲染时间：`RenderingServer.viewport_set_measure_render_time(vp_rid, true)` 之后读 `viewport_get_measured_render_time_cpu()`、`viewport_get_measured_render_time_gpu()` 和 `get_frame_setup_time_cpu()`，单位毫秒。文档说明这个值在 `max_fps` 或 VSync 封顶时仍然能反映真实负载。

**工具链：**
1. **Godot 编辑器远程调试**：一键部署到设备。导出工具链已在本机装好（F11），但还需要接一台真机（USB 或无线 adb）。用 Debugger 里的 Monitors 和 Visual Profiler 按 pass 看 CPU/GPU 耗时，用 Profiler 看脚本函数耗时。
2. **Android GPU Inspector（AGI）**：系统 Profiling 看 GPU 计数器、帧时间线。Frame Profiling 只支持部分 Adreno/Mali 设备，请先查 AGI 支持列表【不确定，按设备核对】。
3. **Snapdragon Profiler**（Adreno 机）：看 GPU busy、带宽、%Shaders busy、温度和频率曲线。
4. **Arm Performance Studio / Streamline**（Mali 机）：看 fragment / non-fragment 队列、overdraw、带宽。
5. **adb**：
   - `adb shell dumpsys gfxinfo <pkg> framestats`：Godot 用 Vulkan 直接出帧，这里的 HWUI 统计**可能不完整**，只作辅助【推断】
   - `adb shell dumpsys SurfaceFlinger --latency <layer>`：看实际上屏间隔（需要找到 SurfaceView 的 layer 名）
   - `adb shell dumpsys meminfo <pkg>`：TOTAL PSS、Graphics、GL mtrack
   - `adb shell dumpsys thermalservice`、`adb shell dumpsys battery`：温控
   - `adb shell am start -W <pkg>/<activity>`：冷启动时间
6. **安装包分析**：Android Studio 的 APK Analyzer，或 `unzip -l` 看 `assets/*.pck` 和 `lib/arm64-v8a/libgodot_android.so` 的大小。

### 7.2 固定测试场景与流程

| 测试 | 场景 | 镜头路径 | 时长 |
|---|---|---|---|
| T1 探索压力 | 村庄 + 山门，竹林画框最密的位置 | 脚本驱动角色从山门沿主路走到分岔口，再返回，循环；镜头跟随固定 | 3 次 × 60 s |
| T2 前景遮挡 | 主角走到前景竹丛后面（触发淡出） | 固定点停 10 s，再左右平移 | 60 s |
| T3 对话 | 立绘加打字机 | 连续播放 10 段 | 60 s |
| T4 战斗 | 回合制战斗，含技能特效 | 脚本自动出招，打完 5 场 | 每场取全程 |
| T5 加载 | 冷启动、进入探索、进入战斗、返回 | — | 各 5 次取中位数 |
| T6 温控 | T1 循环 | — | 30 分钟 |

**采样规则：**
- 每次测试前：重启 App，等待 10 s 预热，丢掉前 5 s 数据（着色器编译和流式加载）。
- 构建：debug 构建用来测 DrawCall、内存等计数器（部分监视器 release 构建不可用）。帧时间以 **release 构建**为准。两种构建都要跑。
- 设备状态：关掉省电模式和“游戏加速”，屏幕刷新率固定 60 Hz 或 120 Hz（需要记录）。
- 每帧记录：帧间隔 `delta`、GPU 时间、CPU 渲染时间、`TIME_PROCESS`。每秒记录一次 DrawCall、Primitives、Objects、显存。
- 统计口径：
  - 平均帧时间 = 帧间隔总和 ÷ 帧数
  - **P95 / P99 帧时间**：帧间隔排序后取百分位
  - **1% low fps**：最慢 1% 帧的平均帧时间换算成 fps
  - 尖刺数：帧间隔 > 50 ms 的帧数，和 > 100 ms 的帧数
  - 3 次重复取中位数。差异 > 5% 时要排查环境

**通过标准（默认档 30 fps，基准机）：**
- 平均帧时间 ≤ 33.6 ms
- P95 ≤ 36 ms，P99 ≤ 40 ms
- 1% low ≥ 25 fps
- 不封顶时 GPU 时间 ≤ 24 ms，主线程 ≤ 12 ms
- 计数器都在第 5 节预算内
- 第 2.3 节的温控标准全部通过

高档 60 fps：P95 ≤ 18 ms，1% low ≥ 50 fps，GPU ≤ 12 ms。

### 7.3 示例采样脚本（只写在文档里，不放进项目）

```gdscript
# perf_probe.gd —— 示例，作为 autoload 临时挂载；文件请勿提交到主分支
extends Node

const SAMPLE_SEC := 60.0
const WARMUP_SEC := 5.0

var _frame_ms: PackedFloat32Array = []
var _gpu_ms: PackedFloat32Array = []
var _cpu_ms: PackedFloat32Array = []
var _t := 0.0
var _vp: RID
var _peak := {"draw": 0.0, "prims": 0.0, "objs": 0.0, "vmem": 0.0, "tmem": 0.0, "pipe_draw": 0.0}

func _ready() -> void:
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)

func _process(delta: float) -> void:
	_t += delta
	if _t < WARMUP_SEC:
		return
	_frame_ms.append(delta * 1000.0)
	_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu())
	_peak["draw"] = maxf(_peak["draw"], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_peak["prims"] = maxf(_peak["prims"], Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_peak["objs"] = maxf(_peak["objs"], Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_peak["vmem"] = maxf(_peak["vmem"], Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	_peak["tmem"] = maxf(_peak["tmem"], Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	_peak["pipe_draw"] = Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
	if _t >= WARMUP_SEC + SAMPLE_SEC:
		_report()
		set_process(false)

func _pct(a: PackedFloat32Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]

func _avg(a: PackedFloat32Array) -> float:
	var sum := 0.0
	for v in a:
		sum += v
	return sum / maxf(1.0, float(a.size()))

func _report() -> void:
	var s := _frame_ms.duplicate()
	s.sort()
	var n1 := maxi(1, s.size() / 100)
	var worst := 0.0
	for i in range(s.size() - n1, s.size()):
		worst += s[i]
	var low1_fps := 1000.0 / (worst / n1)
	var spikes50 := 0
	var spikes100 := 0
	for v in _frame_ms:
		if v > 50.0: spikes50 += 1
		if v > 100.0: spikes100 += 1
	print("PERF frames=%d avg=%.2fms p95=%.2fms p99=%.2fms low1=%.1ffps gpu_avg=%.2f gpu_p95=%.2f cpu_render_avg=%.2f spikes>50=%d >100=%d" % [
		_frame_ms.size(), _avg(_frame_ms), _pct(_frame_ms, 0.95), _pct(_frame_ms, 0.99), low1_fps,
		_avg(_gpu_ms), _pct(_gpu_ms, 0.95), _avg(_cpu_ms), spikes50, spikes100])
	print("PERF peak draw=%d prims=%d objs=%d vmem=%.0fMB tmem=%.0fMB pipeline_draw_total=%d" % [
		_peak["draw"], _peak["prims"], _peak["objs"], _peak["vmem"] / 1048576.0, _peak["tmem"] / 1048576.0, _peak["pipe_draw"]])
```

读取日志：`adb logcat -s godot | grep PERF`。

> 注意：这段脚本本身没有在真机上运行过，API 名已对照 4.7 类参考核实。另外 `get_monitor` 的部分渲染计数器可能有最多 1 秒的更新延迟（文档原话）。

---

## 8. 风险与优先级

基于 Brief 和工程指南推断，工程生成后需要逐条核对。

| 优先级 | 风险 | 依据 | 建议动作（交给 Codex，本文不改仓库） |
|---|---|---|---|
| **P0** | 安卓用 Mobile 渲染，SSAO、体积雾、SSR 不生效，PC 截图和真机画面不一致 | F1；renderers 文档 | 开发期统一用 Mobile；SSAO 改为烘焙或顶点 AO；雾改为深度雾 + 雾片 |
| **P0** | 竹林和草用了大量独立 MeshInstance3D，DrawCall 爆表 | F4、F12 | 植被一律用 MultiMesh + 程序化 ArrayMesh，按区块切分；用 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 验收 |
| **P0** | 植被、雾片、前景淡出叠加造成 overdraw，Mali 机 GPU 超时 | F12；Brief 的 mist、bamboo | 叶片用 alpha scissor，前景淡出改抖动；雾片 ≤ 4；在 Arm Streamline / AGI 里看 overdraw |
| **P1** | 全分辨率 1080p 加后处理，GPU 吃满 | F3 | 3D 缩放 0.75，UI 原生分辨率 |
| **P1** | 方向光阴影距离和分辨率过大；Sprite3D 实时投影 | F2；Brief 的 soft shadows | 按 4.4 节分档；角色先用圆影 |
| **P1** | 安卓 Swappy auto 模式悄悄把帧率降到 30，60 档的测量失真 | ProjectSettings 文档 | 测试时设 `swappy_mode=0` 加固定 `max_fps` |
| **P1** | 本机没有 GPU、没有真机（导出工具链已有），性能数字测不了；软件渲染的截图帧率不能当证据 | F11 | 准备真机加 adb 环境；在 REPORT.md 里如实写“未在真机测量” |
| **P2** | 首次进入场景或战斗时着色器编译卡顿 | Performance 文档的 PIPELINE_COMPILATIONS_* | 加载界面预热战斗特效材质；看 `_DRAW` 计数 |
| **P2** | 水面 shader 读 SCREEN/DEPTH_TEXTURE 的带宽 | Brief 的 water | 低档改成不透明水 |
| **P2** | 精灵表 > 2048、非运行时美术进包，内存和包体膨胀 | F7–F9 | 图集 ≤ 2048；`assets/` 只放运行时资源；导出排除 `docs/` |
| **P3** | 碰撞用 trimesh 或 convex，掉帧 | F5 | 坚持用基本形状 |
| **P3** | 用 `cull_disabled` 修法线问题，片元成本翻倍 | F6 | 修正绕序，用 `generate_normals()` |

---

## 9. 工程生成后的复审清单（只读命令）

```bash
cd /workspace/godogen-shanhe
rg -n "rendering_method|scaling_3d|msaa|screen_space_aa|anisotropic|vram_compression|directional_shadow|positional_shadow|glow|max_fps|frame_pacing|occlusion" project.godot
rg -n "ssao_enabled|ssil_enabled|sdfgi_enabled|ssr_enabled|glow_enabled|fog_enabled|fog_mode|volumetric_fog_enabled" -g '*.tres' -g '*.tscn' -g '*.gd'
rg -n "shadow_enabled|directional_shadow_mode|directional_shadow_max_distance|cast_shadow|OmniLight3D|SpotLight3D" -g '*.tscn' -g '*.gd'
rg -n "MultiMesh|MeshInstance3D.new|instance_count|visibility_range" -g '*.gd' -g '*.tscn'
rg --files -g '*.gdshader' | xargs rg -n "render_mode|SCREEN_TEXTURE|DEPTH_TEXTURE|hint_screen_texture|hint_depth_texture|ALPHA_SCISSOR|ALPHA\b|discard|cull_disabled|TIME"
rg -n "compress/mode|compress/high_quality|mipmaps/generate|process/size_limit|detect_3d" -g '*.import' assets
rg -n "architectures|texture_format|etc2|astc|gradle|min_sdk|target_sdk|export_filter|exclude_filter" export_presets.cfg
find assets -type f -printf '%s %p\n' | sort -nr | head -30
rg -c "create_trimesh_shape|create_convex_shape" -g '*.gd'
```

---

## 10. 交付前自查

- [x] 区分了【项目事实】【文档事实】【建议预算（待实测）】【推断】
- [x] 没有声称任何测量或提升已验证；全文没有真机数据
- [x] 工程文件不存在这一点已写明（1.1），涉及的检查项都标了“未审阅项目”
- [x] Mobile 渲染器的特性（SSAO、体积雾、SSR、SDFGI、SSIL 都不支持；Glow 支持；每网格 8+8 光源）和 Performance 枚举名、ProjectSettings 键名都已对照 4.7 stable 文档核实
- [x] 没有修改仓库，没有安装，也没有运行会写入项目的命令
- [ ] 待办：工程生成后按第 9 节复审；真机实测后用数据替换第 2、5 节的起始预算
