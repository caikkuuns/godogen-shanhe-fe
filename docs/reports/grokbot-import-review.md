# Grok Bot 导入评审（2026-11-23）

## 结论（一句话）
导入成功且**没有覆盖任何现有文件**，但它的前端工程是**较旧的另一条线**（fe worktree HEAD `04e2275`），
不能整包替换我们的 master（`9822258` + 本轮 `e135e97`）。建议：**代码保留我们的，资产/工具/评审记录按需挑选**。

## 基本数据
| 项 | 值 |
|---|---|
| 导入提交 | `e135e97 import: Grok Bot 项目文件（自云端电脑）` |
| 文件数 | 2358（2357 内容文件，SHA256 全部通过） |
| 体积 | 963 MiB |
| 位置 | `incoming/grokbot/`（按来源隔离，未合并进主工程） |
| 现有测试 | 导入后仍全绿：145/145、UI 3/3、WORLD 10/10、BREATH、FOOT_LOCK |
| 原模型 | `assets/glb/*.glb` 未删除 |

## 来源目录
- `godogen-shanhe-fe/` 482 文件 190.8 MiB（HEAD 04e2275，branch fe）
- `godogen-shanhe-be/` 301 文件 62.7 MiB（HEAD 8f68830，branch be）
- `godogen-shanhe/` 416 文件 161.4 MiB（旧 master cda2259）
- `wuxia-team/` 888 文件 172.4 MiB（策划/美术/QA 报告与素材）
- `shenyan-img3d/` 184 文件 189.8 MiB（TripoSR 管线与渲染）
- `wuxia-delivery/` + `shanhe-delivery/`（0.4.0 构建与 debug apk）

## 代码差异（scripts/scenes/data/tests/shaders/tools 共 148 vs 105 个文件）
| 类别 | 数量 | 说明 |
|---|---|---|
| 内容相同 | 71 | 同源，无需处理 |
| **同名不同内容（冲突）** | **27** | 见下表，需逐个裁决 |
| 只在我们的 | 50 | 我们的新系统（encounters / regions / npc_db / hidden_quest / game_clock 等） |
| 只在它的 | 7 | 可能有价值的工具脚本 |

### 27 个冲突文件（同名不同内容）
README.md、project.godot、scenes/main.gd、scenes/render_captures.sh、
scripts/autoload/{dialogue_db,game_state}.gd、
scripts/battle/battle_stage.gd、scripts/ui/{battle_panel,dialogue_panel,hud,ui_theme,virtual_joystick}.gd、
scripts/world/{character_anim,foot_lock,idle_breath,npc,player,player_camera,sheath_follow,tassel_hang,toon_model}.gd、
shaders/{toon_char,toon_char_front}.gdshader、tests/run_all.sh、tests/test_foot_lock.gd

### 只在它那边的 7 个（建议吸收）
tools/capture_down.gd、tools/dump_sword.gd、tools/img3d/{afternoon_p0_meshes,fix_fill_uvs,polish_round2}.py

## 合并策略（建议）
1. **保留我们的代码主线**：不整包替换 `scripts/`、`scenes/`、`data/`、`tests/`；
   我们的工程多了开放世界/机缘/隐藏任务/NPC 池/时钟等系统，且测试覆盖 145+10。
2. **吸收它的资产与记录**：`wuxia-team/art/`（大量角色/场景原始图与评审对照图）、
   `wuxia-team/art/review-notes/`（历轮美术评审记录）、`shenyan-img3d/`（TripoSR 管线）。
   这些只读引用，不进入运行时代码路径。
3. **吸收它的工具脚本**：上面 7 个 tools 脚本，逐个 review 后拷进 `tools/`。
4. **冲突文件的处理**：逐个人工 diff（27 个），只把确认更好的实现搬过来，
   不做 `git checkout` 覆盖，避免丢掉我们的开放世界改造。
5. `incoming/` 目录保留为只读归档；确认吸收完后可移到 `/DATA/GameArchive/grokbot-20261123/`。

## 下一步
- [ ] 逐个 diff 27 个冲突文件，输出「吸收/丢弃」清单
- [ ] 从 `wuxia-team/art/` 挑出比现有 `docs/ref-characters-*` 更清晰的素材
- [ ] 把 7 个 tools 脚本拷入 `tools/` 并跑一次
- [ ] 更新 `.shift/handover.md`，记录本轮导入
