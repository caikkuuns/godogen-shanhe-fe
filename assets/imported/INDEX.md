# assets/imported 索引（第八轮 Grok Bot 资产吸收）

来源：`incoming/grokbot/wuxia-team/art/`（Grok Bot 云端电脑的美术工作区，只读归档）。
本目录是拷贝工作副本；`incoming/` 原件不动。启用状态指是否已接入运行时代码。

| 文件 | 来源路径 | 尺寸(px) | 用途 | 状态 |
|---|---|---|---|---|
| props/prop_stonelantern_r4b.png | round4/prop_stonelantern_r4b.png | 506×625 | 石灯幢修订版（r4 顶盖太日式，r4b 改中式亭顶+须弥座+莲瓣），画布/锚点/高度与 r4 完全一致，直接换图 | **已启用**（BuildingFactory.stone_lantern 运行时 + world_builder PROPS） |
| props/prop_stonelantern_shadow_r4b.png | round4/ 同名 | 506×625 | 配套投影 | **已启用** |
| props/round4.json / round4b.json | round4/ 同名 | - | 第四轮道具卡（尺寸/锚点/实物高度依据） | 参考存档 |
| scenery/gate_L0_ground.png | art/gate_L0_ground.png | 911×886 | 村口牌坊分层：地面层 | **已启用**（BuildingFactory.mountain_gate，运行时生效） |
| scenery/gate_L1_back.png | art/gate_L1_back.png | 911×886 | 村口牌坊分层：后柱/墙（画在角色之后） | **已启用**（BuildingFactory.mountain_gate） |
| scenery/gate_L2_front.png | art/gate_L2_front.png | 911×886 | 村口牌坊分层：屋顶+前柱（画在角色之前） | **已启用**（BuildingFactory.mountain_gate；regions.json feature 死值 "shanmen"→"gate" 后首次生成） |
| scenery/gate_layers.json | art/gate_layers.json | - | 分层 z 序、锚点、可行走门洞多边形、柱基阻挡区 | 参考存档（数值已折算进 world_builder） |
| scenery/gate.png | art/gate.png | 911×886 | 牌坊单层合并版（无分层） | 未启用（分层版更好） |
| scenery/house.png | art/house.png | 910×849 | 民居（白墙+瓦顶+木门格窗） | **已启用**（BuildingFactory.village_house，运行时生效） |
| scenery/bamboo_v3a.png | art/bamboo_v3a.png | 514×925 | 竹丛画稿 A | 未启用 |
| scenery/bamboo_v3b.png | art/bamboo_v3b.png | 622×744 | 竹丛画稿 B（更密、第四轮 v3b 定稿） | **已启用**（ChunkBuilder._build_bamboo，运行时生效） |
| scenery/bamboo_v3b_shadow.png | art/bamboo_v3b_shadow.png | 622×744 | 配套投影 | **已启用**（竹丛落地影 MultiMesh） |
| scenery/bamboo_v3a_shadow.png | art/bamboo_v3a_shadow.png | 514×925 | 竹丛 A 投影 | 未启用 |
| scenery/rock_v2.png | art/rock_v2.png | 729×816 | 岩石修订版（比 rock.png 干净） | 未启用 |
| scenery/rock_v2_shadow.png | art/rock_v2_shadow.png | 729×816 | 岩石投影 | 未启用 |
| scenery/waystation.png | ch2/waystation.png | 2092×1940 | 第二章驿亭建筑 | 未启用（第二章未接入主线） |
| scenery/waystation_shadow.png | ch2/waystation_shadow.png | - | 驿亭投影 | 未启用 |
| terrain/ground_grass_tile.png | art/ground_grass_tile.png | 512×512 | 无缝草地 tile（顶视） | **已启用**（ChunkBuilder._terrain_mat，替代噪声贴图） |
| terrain/ground_dirt_tile.png | art/ground_dirt_tile.png | 512×512 | 无缝土路 tile（顶视） | 未启用（OpenWorld 土路走顶点色，混合 shader 只接了竖切地面；待下轮评估） |
| terrain/path_edge_grass_over_dirt.png | art/path_edge_grass_over_dirt.png | 512×512 | 路缘草压土过渡贴图 | 未启用（用 shader 混合替代） |
| portraits/gesancheng_portrait_default.png | ch2/portraits/ 同名 | - | 葛三成 立绘（平静） | 未启用（ch2 角色未入对话库） |
| portraits/gesancheng_portrait_angry.png | ch2/portraits/ 同名 | - | 葛三成 立绘（怒） | 未启用 |
| portraits/linzhaowan_portrait_smile_v2.png | ch2/portraits/ 同名 | - | 林照晚 微笑立绘 v2 | 未启用 |
| backgrounds/battle_bg.png | art/battle_bg.png | 2048×1152 | 战斗远景背景 | 未启用（战斗为 3D 场景，替换是伤筋动骨的决定，先归档） |

## 没拷的（原因）

- `round4/` 其余图标与道具（icon_*_r4、prop_crate/fence/signpost/well_r4）：与 `assets/icons/`、
  `assets/props/` 现有文件 SHA 逐一比对**完全相同**，无需再拷。
- `characters/` 大部分 v2/v3 帧图：与 `docs/ref-characters-v2|v3/` 同源同名，现有更全。
- `art/ch2/` 战斗姿态（葛三成/打手 battle_*）：第二章战斗未接入，等 ch2 系统落地再取。
- `art/review-notes/`：历轮美术评审记录，体积大且是流程文档；留在 `incoming/` 只读参考。

## 更新规则

后续每吸收一张新图，在表里加一行并改状态；未启用项要写明卡在哪
（性能 / 待系统 / 决策未定），避免下一轮重新考古。
