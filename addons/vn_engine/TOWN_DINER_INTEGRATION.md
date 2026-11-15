# Native runtime integration in Town Diner (D072-R1)

Upstream: https://github.com/kaanakgundogdu/godot-vn-engine
Commit: a2231b2dd985e0ca045f88b9cea993e1eb58a0c6 (0.23.0), MIT.

The editor plugin is enabled. The opening uses VNEngineMain → VNEngineStageScreen
→ VNEngineStoryRunner → VNEngineDialogUI, the native scenario parser, character
and background managers, auto/skip and the read-only log. Content lives in
`content/story/vn/`. The plugin bakes the scenario into `.txt.res` on export.
The local stage inherits the upstream stage; it does not reimplement the parser
or dialogue progression. Later chapters/daily conversations still use TDDialogue.

`src/story/vn_stage.gd` owns the short-lived host instance and SubViewport.
`td_cg` and `td_name` are blocking custom commands. A generation token and weak
host reference reject stale callbacks. CG remains the existing AnimationPlayer
scene, not textual narration. TDDialogueView projects context for StoryGuide;
it never ticks TDDialogue while the native opening runs. Chapter completion
alone emits the existing game completion callback. Profile remains the only
save authority; native read history is ephemeral, not a mid-scene save feature.

Local patches (standalone defaults remain available):

- Main `host_managed`: memory-only SaveData and Settings; no window/audio settings,
  separate menu, independent saves or dev overlay. On exit break the stack cycle.
- SaveData memory mode covers constructor, flow snapshots, slot queries and flush.
  SaveSystem rejects independent disk save/load in hosted mode.
- DialogUI hosted shortcuts reject quicksave/load and rollback; Runner also
  guards those calls. `next_node`/choices respect pending block and input lock.
  `cancel_host` ends pending coroutine without continuing the script.
- Game rejects deferred chapter start after detachment. When loading UI is
  disabled it does not issue uncollected threaded resource requests (four leaked
  engine request tokens reproduced on 4.7.2 before this fix).
- Registry knows the two host command names in both editor baking and runtime;
  command objects are registered on the real per-session bus.
- VideoSystem uses Master without warning in hosted mode when Music bus is absent.
- Export plugin temporary bake is under `.godot/`, never player data, and rejects
  parse errors. The export checker requires the baked opening and its assets.
- BackgroundSystem's optional runner annotation is Node to break the upstream
  circular scene preload in Godot 4.7.2; signals/calls are unchanged.

The project stage supplies Chinese UI, isolated Cast copies for names, original
portrait AtlasTextures, and hides separate save/menu buttons. Sample game,
editor tools and dev entry are excluded from production. Do not upgrade this
dependency without rerunning the native scenario, cancellation, save isolation,
ordinary dialogue and actual exported-pack checks.
