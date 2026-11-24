# 《山河剑行》场景美术方向（Godot HD-2.5D 参考）

**状态：参考稿，未在引擎中测试。** 所有数值都是起始建议，要在 Godot 4.7 里实际调。
依据：现有 0.4.0 素材（house / gate / rock_v2 / bamboo_v2/v3 / ground tiles / battle_bg）的实测主色，加上参考图的淡蓝白水墨气质（只参考画风）。配套图：`scene_art_direction_board.jpg`。

## 1. 调色板（hex）
| 用途 | 色值 | 来源 / 说明 |
|---|---|---|
| 雾 / 天空高光 | `#DDE6EE` `#C9D6E2` | 淡蓝白，参考图气质 |
| 远山 / 远景冷灰 | `#9AA9B8` `#7D8B99` | 空气透视 |
| 瓦顶 | `#4B4441` `#6E6661` `#25201D` | house.png 实测 |
| 白墙（旧） | `#ACA29B` `#928881` | house.png 实测 |
| 木构 / 门楼 | `#544742` `#4A261D` `#2D2221` | gate.png 实测 |
| 岩石 | `#C4B59D` `#B8A590` `#776D63` `#35393C` | rock_v2.png 实测（暖灰亮面 + 冷暗面） |
| 竹 | `#8B985D` `#697847` `#4A5A35` `#313F26` `#172816` | bamboo_v2.png 实测 |
| 草地 | `#84884F` `#777C48` `#6D7342` | ground_grass_tile 实测 |
| 土路 | `#C9B492` `#BEA988` `#B19D7D` | ground_dirt_tile 实测 |
| 水 | `#6F8E9A`（浅）→ `#2F4A55`（深） | 建议值 |
| 角色点缀 | 沈砚 `#ECEBE6`/`#A9C3E2`/`#5B78A6`；林照晚 `#F2C9CF`/`#D98A9A` | 角色设定 |
| 阴影色 | `#12161E`，透明度 0.45-0.55 | 和 blob shadow 一致 |

原则：环境整体偏暖灰绿、低饱和；冷色留给雾和远景；最亮、最纯的颜色留给角色（白衣、粉衣），保证人物跳出来。

## 2. 灯光（key / fill / rim）
| 灯 | Godot 节点 | 方向 | 色温 / 颜色 | 强度起点 |
|---|---|---|---|---|
| 主光 key | DirectionalLight3D | 来自画面左上：rotation_degrees ≈ (-50, -135, 0)（yaw 按场景朝向调），阴影投向右下 | 约 5200-5600K，`#FFF1DC` | light_energy 1.2-1.6；shadow_enabled，PSSM 2 splits，shadow_blur 1.5-2 |
| 补光 fill | 只用 WorldEnvironment 环境光（不加第二盏灯） | 天空方向 | 约 7500K，`#C9D6E2` | ambient_light_energy 0.5-0.7，ambient_light_sky_contribution 0.6 |
| 轮廓 rim | 第二盏 DirectionalLight3D，不投影 | 来自右后上方 rotation_degrees ≈ (-25, 45, 0) | 冷白 `#DCE8F5` | light_energy 0.3-0.5，shadow_enabled=false |
| 角色 | Sprite3D 默认受光会变灰；建议 `shaded=false` + 自己加 rim/描边，或者 shaded 加 0.85-1.0 的自发光 | — | — | 以和场景同屏对比为准 |

## 3. 雾
- Depth fog：`fog_enabled=true`，fog_light_color `#DDE6EE`，fog_density 0.008-0.015（按场景尺度调），fog_sky_affect 0.6，fog_aerial_perspective 0.3-0.5。
- Height fog（山谷雾 / 竹林雾）：fog_height = 地面 +0.5~1.0 m，fog_height_density 0.25-0.5，只压住地面和远景，不盖住人物上半身。
- 可选 Volumetric fog：density 0.01-0.02，albedo `#E6ECF2`，手机端建议关掉。

## 4. 天空 / 环境
- ProceduralSkyMaterial：sky_top_color `#B9CADB`，sky_horizon_color `#E3E9EE`，ground_horizon_color `#C7CBC4`，ground_bottom_color `#6E7466`，sun_angle_max 30。
- tonemap：Filmic 或 AgX，exposure 1.0，white 6；glow 低（intensity 0.3，bloom 0.05）只给雾和白衣一点光晕。
- SSAO：radius 1.0，intensity 1.5-2.0，手机端可以关；SSIL 关掉。
- 后处理（可选，偏水墨）：轻微纸纹叠加（opacity 5-8%）+ 饱和度 -10%。

## 5. 材质参考（StandardMaterial3D / ORM）
| 材质 | Albedo 范围 | Roughness | Metallic | 备注 |
|---|---|---|---|---|
| 石阶 / 岩石 | `#776D63` - `#D5C1AC` | 0.85-0.95 | 0 | 亮面偏暖、暗面偏冷；缝里加苔绿 `#5E6B3E`；AO 要重 |
| 木构（柱、梁、门） | `#2D2221` - `#7F7570` | 0.7-0.85 | 0 | 旧木偏灰褐；漆面只在门楼局部用 0.5 |
| 瓦顶 | `#25201D` - `#6E6661` | 0.75-0.9 | 0 | 筒瓦起伏用法线；檐口暗一档 |
| 白墙 | `#928881` - `#D8D2CA` | 0.9 | 0 | 下半段加水渍和苔痕（贴花） |
| 竹 | 竿 `#697847`-`#8B985D`，叶 `#172816`-`#4A5A35` | 竿 0.5-0.6，叶 0.7 | 0 | 叶片 alpha scissor 0.5 + 风摆 shader（顶点 sin，幅度 0.05-0.1 m，频率 0.6-1.2 Hz）；叶子背面透光（backlight `#9FB070`，0.3） |
| 水 | `#2F4A55` - `#6F8E9A` | 0.05-0.15 | 0 | 透明 + 菲涅尔反射天空色；岸边加白泡沫线；流速很慢 |
| 布（旗、帘） | 白 `#E8E4DC`、靛 `#4E6283` | 0.9 | 0 | 双面 + 轻微透光；风摆幅度比竹子小 |
| 草 / 地被 | `#6D7342` - `#8F9157` | 0.9 | 0 | 草丛用 MultiMesh 卡片；接地处压暗 15%；土路用贴图混合，边缘用 `path_edge_grass_over_dirt.png` 的软边 |
| 土路 | `#B19D7D` - `#D0BC9A` | 0.95 | 0 | 车辙、脚印法线很浅 |

## 6. 角色和场景的配合
- 角色是 Sprite3D 广告牌，地面阴影用 `characters/shadow_blob_v2_*.png`（贴地 decal 或平面 quad，放在脚底锚点）。
- 人物尺度先在 A（门楼 ≈2.2 人高）和 B（门 ≈1.18 人高）两种方案里选一种，见 `characters/characters_v2.json` 的 `scale_options`。
- 前景遮挡（竹、门楼前柱）挡住人物时，按 scene-layout-notes 做 40% 透明或描边。
