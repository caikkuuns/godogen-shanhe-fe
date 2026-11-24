# 服务器开发说明（Claude Code 必读）

这是《山河剑行》项目，从用户之前的机器搬过来的，**项目内文档才是权威需求**：

- `BRIEF.md` — 本轮目标 + 大量 Update（战斗规则、UI 计划、美术 v2、性能决策都以它为准）
- `README.md` — 已建成 / 待办 / 资产表（每次改动后要更新）
- `docs/battle-v1-godot.md`、`docs/godot-ui-plan.md`、`docs/dialogue-v1.md`、`docs/shanhe_android_perf_budget.md` — 权威规格
- `docs/ref-characters-v2/`、`docs/ref-characters-v3/` — 美术参考与立绘

## 工作约束
- Godot **4.7.2**，GDScript，**主工程保持 Mobile 渲染器**（不要为了网页导出改主工程设置）
- 只在**本目录内**改动。不要动 ~/games 以外、不改系统、不装系统包、不联网下载素材
- 每轮改完必须自检并贴出结果：
  `GODOT=$HOME/.local/bin/godot bash tests/run_all.sh`
  要求 `145/145` 通过、UI 场景测试 `ok`、BREATH/FOOT_LOCK `ok`，不新增 ERROR
- 新增代码沿用现有结构：`scenes/`、`scripts/{autoload,battle,dialogue,ui,world}/`、`data/`、`tests/`
- 保持 30fps 预算、3D scale 0.75、无 SSAO/SSR/SDFGI/体积雾（见 BRIEF PERF DECISION）
- 用手写中文注释；改动小而可回滚，不要大重构
- 需要看画面时用 `scenes/render_captures.sh`（xvfb），不要假设有 GPU

## 已知问题（可顺手修）
- `scripts/ui/hud.gd:100` 引用 `res://docs/ref-characters-v3/shenyan_portrait_v2.png`，**文件不存在** → 换 v2 里的立绘或加兜底
- 本包没有 .git 历史，服务器上已重新 `git init`

## 服务器上的验证命令（照抄，别改）
```bash
export PATH=$HOME/.local/bin:$PATH
GODOT=godot bash tests/run_all.sh                      # 必须全绿
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json \
  XVFB_SCREEN=1280x800x24 CAPTURE_RESOLUTION=960x540 bash scenes/render_captures.sh   # 截图
```
- 中文字体：`assets/fonts/shanhe_serif.otf`（思源宋体 SC），`project.godot` 的 `gui/theme/custom_font` 已设置，别删
- 网页构建由人工在服务器做（Compatibility 副本），不用你处理
