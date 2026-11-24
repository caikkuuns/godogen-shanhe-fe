class_name CharacterBillboard
extends RefCounted
## 已退役（第三轮：人物全部改为 3D 卡通模型）。
##
## 历史：这里曾是 Sprite3D 立绘组件（FIXED_Y 广告牌、8 方向贴图、blob 影）。
## 用户判定“像纸片人”后，探索态人物改由 `scripts/world/character_model.gd`
## 用现有 GLB + toon 材质 + ink_hull 描边实现。
##
## 本文件仅作回滚参考保留：
## - 不再被 player.gd / npc.gd / open_world.gd / 测试引用
## - 不包含任何 Sprite3D 实例化代码
## - 对话/HUD 的 2D 立绘头像路径在 `OpenWorld.PORTRAITS` 与 `DialogueDB` 中
