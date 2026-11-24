# 《山河剑行》Godot 4.7.2 UI 落地方案（依据 docs/ui-spec.md v2）

范围：只定 UI 实现方式，不加新玩法。标"建议"的为推荐做法；所有数值仍需在 captures 截图与真机上核对。

## 1. 项目设置（project.godot）
- display/window/size/viewport_width=1920, viewport_height=1080
- display/window/stretch/mode="canvas_items"，stretch/aspect="expand"（高度固定 1080，20:9 时可见宽度变成约 2400，多出部分留给场景）
- display/window/handheld/orientation="sensor_landscape"
- input_devices/pointing/emulate_touch_from_mouse=true（桌面调试触控）
- 3D 相机用 keep_height，20:9 只多看两侧场景，不放大 UI。

## 2. 单位换算（dp → 设计像素）
- 高度固定为 1080 时：在约 360dp 高的手机上，1dp ≈ 3 设计像素。**基准规则：设计像素 = dp × 3**。
- 屏幕更高的设备（平板等）上，按比例缩放会让控件变小，所以在 Autoload `UiScale.gd` 里算真实下限：
  ```gdscript
  func dp(v: float) -> float:
      var dpi := DisplayServer.screen_get_dpi()          # Android 有效
      var win_h := float(DisplayServer.window_get_size().y)
      return v * (dpi / 160.0) * (1080.0 / win_h)
  func min_px(v_dp: float, base_px: float) -> float:
      return max(base_px, dp(v_dp))
  ```
  控件尺寸取 min_px(dp 下限, 设计值)，在 `get_viewport().size_changed` 时重新计算。

| 规格（dp/sp） | 设计像素（×3） |
|---|---|
| 可点热区 44 / 推荐 48 | 132 / 144 |
| 主键 64（下限 56） | 192（168） |
| 摇杆底盘 104，拇指 44 | 312，132 |
| 间距 8 | 24 |
| 对话正文 14~16sp（下限 13） | 42~48（39） |
| 按钮字 11~12sp（下限 11） | 33~36（33） |

## 3. 场景树与锚点
```
UI (CanvasLayer, layer=10)
└─ SafeArea (Control, 锚点 FULL_RECT, offsets 由安全区脚本设置)
   ├─ StatusPanel     锚点左上 (0,0)：头像 108、HP 条 330×15、内力条 330×10
   ├─ MenuBar         锚点右上 (1,0)，HBoxContainer 向左排：按钮最小 132×132，图标 72，间距 12
   ├─ QuestTracker    锚点左上，offset_top 在头像下方约 130，宽 ≤510，最多 2 行，点击折叠
   ├─ JoystickArea    锚点左下区域：anchor_left 0, right 0.4, top 0.45, bottom 1
   ├─ ActionCluster   锚点右下 (1,1)：主键 192，右/下边距 48；技能 132 呈弧形排在主键左上，间距 ≥24
   ├─ InteractPrompt  （见第 6 节）
   ├─ DialogueLayer   默认隐藏
   └─ BattleHUD       默认隐藏
```
- 中央视区：安全区中部约 50% 宽 × 55% 高里不放常驻控件。建议给常驻控件加 `hud_persistent` 组，测试时检查它们都不进入这个矩形。
- 统一用锚点加 offset，不写死绝对坐标。

## 4. 安全区（SafeArea.gd）
```gdscript
func _ready(): get_viewport().size_changed.connect(_apply); _apply()
func _apply():
    var win := Vector2(DisplayServer.window_get_size())
    var vis := get_viewport().get_visible_rect().size
    var s := vis / win
    var safe := Rect2(DisplayServer.get_display_safe_area())  # 屏幕像素
    var pad := UiScale.dp(8)
    offset_left   = safe.position.x * s.x + pad
    offset_top    = safe.position.y * s.y + pad
    offset_right  = -(win.x - safe.end.x) * s.x - pad
    offset_bottom = -(win.y - safe.end.y) * s.y - pad
```
- 桌面上安全区等于整个窗口，只剩 8dp 内边距。Android 上读的是系统真实的挖孔和手势条 inset，不设固定大边距。
- 注意：safe area 返回的是屏幕坐标，窗口不是全屏或有偏移时，要先减去 `DisplayServer.window_get_position()`。

## 5. 虚拟摇杆（VirtualJoystick.gd，挂在 JoystickArea）
- 动态摇杆：在 JoystickArea 内任意位置按下就在该点出现底盘，松手回到默认位置并半透明。默认圆心约在 (0.13W, 0.72H)。
- **必须用 `_input` 处理 InputEventScreenTouch/ScreenDrag，并记录 touch index**。不要用 `_gui_input`：Godot 只把第一根手指模拟成鼠标，否则拇指按着摇杆时右侧按钮会收不到点击。
- 输出：死区 0.15，把方向写进输入动作（`Input.action_press("move_left", strength)` 等），或者直接给出 `Vector2`。键盘 WASD/方向键走同一套动作，玩家脚本不区分输入来源。
- 右侧按钮同理，建议用 TouchScreenButton，或者在 `_input` 里按 touch index 做命中检测的自定义 Control，保证左手推摇杆时右手点按钮能生效。这只是基础操作的正确性，不算新功能。
- 按下反馈：缩放到 0.92，加高光，约 80ms。

## 6. 交互提示
- 建议：靠近可交互对象（NPC、宝箱、门）时，在它头顶显示一个小 Label3D 或 Sprite3D 图标（billboard，约人物高度的 0.3），同时右下主键的文字改成“交谈”“调查”等。
- 不在屏幕中央弹常驻提示框。键盘按 E/空格触发，和主键是同一个动作。
- 多个对象同时在范围内时，取最近的那个；主键只对应一个目标。

## 7. 对话面板与立绘
- DialoguePanel：anchor_left 0.2，anchor_right 0.8，anchor_top 和 anchor_bottom 都设为 1，offset_top -300，offset_bottom -36（高度 ≤300，即 100dp）。
- 内部：说话人名字 Label 用 42px 加阵营色；正文 RichTextLabel 用 42~48px，行距约 1.4，打字机效果用 `visible_ratio` 加 Tween，点一下直接显示全文、再点一下翻页。
- 选项：VBoxContainer 放在面板上方靠右，每个 Button 最小高度 132、间距 24，不覆盖正文。
- 立绘：两个 TextureRect（左右各一），expand_mode=IGNORE_SIZE，stretch_mode=KEEP_ASPECT，底边贴面板上沿，高度 ≤630（210dp），水平位置不压正文。说话方 modulate=白色，另一方 Color(0.55,0.55,0.55,0.85)。对话结束后两个立绘都隐藏并释放纹理引用。
- 数据来自 story-data.md；立绘用 ref-characters 里的素材，按 characters.json 的锚点对齐。

## 8. 战斗 HUD（只定布局，保留现有回合规则）
- 进入战斗时隐藏 JoystickArea、QuestTracker 和交互提示；StatusPanel 可保留。
- 指令按钮：在右下 ActionCluster 区域竖排或沿弧形排，每个 ≥132×132、间距 ≥24，不横铺底部整条。
- 头顶血条：用 Control 跟随角色，每帧把屏幕位置设为 `camera.unproject_position(actor.global_position + Vector3(0, head_h, 0))`，宽约 360（120dp），高 12。不压角色脸，被相机背面遮住时隐藏（用 `camera.is_position_behind()` 判断）。
- 选目标：在 3D 场景里点角色，用射线查询或给角色加 Area3D 碰撞体，碰撞范围不小于角色包围盒。
- 战斗背景按 16:9 设计。20:9 下按宽度铺满时，上下各裁掉约 10%，所以人物站位放在画面高度 10%~90% 之间。

## 9. 主题（Theme .tres）
- 面板和按钮：StyleBoxFlat，bg_color #141414，透明度 0.6；border 3px（1dp），颜色 #B08D57，透明度 0.8；corner_radius ≤18（6dp）。
- 字体：思源宋体或思源黑体（Noto CJK SC）择一做正文，书法字只用在标题。所有 Label 设 outline_size 3、描边色 #000 透明度 0.7。
- 禁止米色大方块按钮和大面积实色铺底；常驻 HUD 总面积 ≤ 屏幕 15%。

## 10. 截图验收（captures/ 出图后逐项核对）
用 `--resolution 1920x1080` 和 `2400x1080`（另加 `1280x720` 抽查）各截探索、对话、战斗三张：
1. 所有控件都在安全区内，没有被裁切；20:9 下 HUD 贴着两边，中间多出的宽度只留给场景。
2. 中央视区里没有常驻 HUD，人物和建筑完整可见。
3. 可点热区 ≥132 设计像素（44dp），相邻间距 ≥24；摇杆底盘约 312，不超过屏高 30%。
4. 对话正文 ≥39px，最小字号 ≥33px，亮背景和暗背景上都清楚。
5. 立绘不遮正文，对话结束后消失；战斗按钮只在右下，不铺满底部。
6. 推着摇杆的同时点右侧按钮，按钮能生效（需要真机或多点触控模拟器）。

建议增加一个无界面运行的检查：遍历 `hud_persistent` 组里的控件，断言它们的 `get_global_rect()` 在安全区内、尺寸不小于下限，并且不和中央视区相交。
