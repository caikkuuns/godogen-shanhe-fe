# Brief: 《山河剑行》HD-2.5D (Godot 4.7, GDScript)

Original offline wuxia game, fullscreen landscape (target 1920x1080, Android later). This is a finished brief: make reasonable calls, keep steady progress, do not block.

## Goal of this round (vertical slice)
1. HD-2.5D look: real 3D scene (low-poly/CSG/procedural meshes + shaders: water, mist, wind-swayed bamboo, soft shadows, SSAO/glow, warm-cool ink-wash palette) with a tilted perspective/orthographic camera following the player; characters as HD billboard sprites (Sprite3D, pixel-perfect, foot-anchored, with shadow) using the art in `docs/ref-characters/` (see characters.json for anchors). Original art only.
2. Exploration: village + mountain gate area, 4/8-dir movement (keyboard + on-screen virtual joystick for touch), collision, interact prompt.
3. Dialogue: half-body portrait panel, typewriter text, choices; content from `docs/story-data.md` (leads 沈砚 male, 林照晚 female).
4. Battle: turn-based per `docs/gameplay-spec.md` (keep it simple if spec is large), win/lose flow back to exploration.
5. UI per `docs/ui-spec.md`: landscape HUD, touch targets >= 44dp equivalent, safe-area margins.
6. Local save (user://), no network, no server, no invented auth. Cloud save is out of scope.

## Constraints
- No paid asset generation (no API keys configured). Use the provided PNGs plus procedural geometry/shaders; placeholders must look intentional.
- Keep README.md updated: built / left / asset table.
- Add GUT-free minimal headless tests (a `tests/run_tests.gd` run with `godot --headless -s`) for save/load, dialogue parsing, battle damage/win/lose.

## Proof
- Run headless import + tests; capture screenshots of exploration, dialogue, battle with `xvfb-run` into `captures/`, look at them and iterate on visual quality at least twice.
- Try Android export: if export templates / Android SDK are missing, try installing templates for 4.7.2 into ~/.local/share/godot/export_templates; if still blocked, document exactly what is missing, don't fake an APK.
- Finish with REPORT.md: what works (verified), what's unverified, test output, screenshot list, known issues. Commit to git.

## Update (from design team)
- Battle v1 rules are now authoritative in `docs/battle-v1-godot.md` (single fight 沈砚 vs 厉横, exact numbers and 8 headless test points). Implement battle to match it exactly.
- UI implementation plan is authoritative in `docs/godot-ui-plan.md` (1920x1080 canvas_items+expand, sensor_landscape, SafeArea from DisplayServer safe area, multi-touch joystick in _input by touch index, Label3D interact prompt, dialogue/battle HUD sizes). Follow it, and add the headless HUD safe-area/size check it suggests.
- Android export toolchain is installed and verified (see `docs/godot-android-export-notes.md`): templates 4.7.2, JDK17, SDK, debug keystore, editor settings. Add export_presets.cfg (Gradle off, arm64-v8a, landscape) and set textures/vram_compression/import_etc2_astc=true; export a real debug APK to `build/shanhe-debug.apk`.
- Dialogue content and schema: load `docs/dialogue-v1.json` (schemaVersion 1) per `docs/dialogue-v1.md`; map its proposed quest/flag/interact IDs onto your implementation, setFlags only committed on end node, NPCs without portraits use name-only panel.
- PERF DECISION (overrides earlier lines): use the **Mobile** renderer everywhere (desktop captures too). No SSAO/SSR/SDFGI/volumetric fog: use baked/vertex-colour AO, depth/height fog, glow, round blob shadows under characters. Bamboo/grass via MultiMesh + procedural ArrayMesh, chunked (overrides the per-instance advice in godot-gdscript.md). Foliage alpha scissor, dither fades, max 4 fog cards. Target 30fps default, 3D scale 0.75. Budgets in `docs/shanhe_android_perf_budget.md`.
- Battle/dialogue integration: on defeat "再战" restarts battle directly (no replay of liheng_prebattle); persist battle.liheng.won to local save before returning to exploration; enemy "蓄力" telegraph (log + overhead marker) is mandatory.
- ART v2 (prefer over v1): `docs/ref-characters-v2/` 8-direction walk (4 frames, 420x500, anchor 210,476) + idle + blob shadows + battle images, `characters_v2.json`. Use the 8 hand-drawn directions, do NOT mirror at runtime (overrides asset-gen single-direction+flip advice). shenyan upright walk plays frames 0-1-2-1. Camera pitch about -45 deg, Sprite3D billboard FIXED_Y; scale so 沈砚 = 1.70 m (pixel_size ~0.00386), size doors/houses to that. Scene palette/lighting/materials in `docs/scene_art_direction.md`.
