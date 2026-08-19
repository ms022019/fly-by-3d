# 実装指示書: Fly By 風ゲートくぐり (3Dゲーム)

> **このファイルを読んだ Claude へ。** これは新規セッションが調査からやり直さずに実装へ入るための引き継ぎ書です。
> 前セッションで得た実測値・踏んだ地雷・有効だった手順をすべて含みます。
> **まず「0. 最初に打つコマンド」を実行して現状を確認してから着手してください。**

## やること

既存の Ball Collector 3D の骨組みを流用し、**ドローンが空中の連続するリングをくぐる 3D ゲーム**を作る。
godot_rl_agents 公式サンプルの Fly By に相当するもの。人間もプレイでき、PPO で AI も学習する。

---

## 0. 最初に打つコマンド

```bash
cd /workspaces/t_0818_3DGame
cat README.md                       # 既存ゲームの全体像 (構成・実測値・制約)
ls game/scripts game/scenes tools   # 流用元のファイル
godot --headless --path game --import   # パースエラーが無いことを確認
```

環境の確認（すべて導入済みのはず）:

```bash
godot --version                     # 4.4.stable (非 .NET ビルド)
python -c "import godot_rl, stable_baselines3, torch; print('ok')"
ls ~/.local/share/godot/export_templates/4.4.stable/ | wc -l   # 35 なら OK
```

---

## 1. 既にあるもの（Ball Collector 3D）

**動作確認済み・完成済み**。壊さないこと。これが流用元になる。

```
game/
  scenes/  main.tscn(入口) play.tscn(人間) train.tscn(学習/観戦)
           arena.tscn player.tscn target.tscn
  scripts/ boot.gd play.gd train.gd arena.gd player.gd target.gd
           ball_ai_controller.gd world_view.gd
  addons/godot_rl_agents/          公式プラグイン
tools/     train.py play_ai.py godot_launcher.py serve_web.py
models/    ball_collector.zip (学習済み)
```

達成済みの成績（新ゲームでも同じ基準で評価すること）:

| プレイヤー | 60秒あたりの取得数 |
|---|---|
| 学習前（ランダム） | 0.2 |
| 手書きの貪欲方策 | 36 |
| PPO 18万ステップ（約2分） | 64 |

### 実行コマンド

```bash
# 人間がプレイ（ブラウザ・推奨）
python tools/serve_web.py           # → http://localhost:8000
# 再エクスポートが必要なとき
godot --headless --path game --export-release "Web" ../build/web/index.html

# 学習
python tools/train.py --steps 300000

# AI のプレイを観る
python tools/play_ai.py             # --headless でスコアのみ
```

---

## 2. そのまま流用できるもの（再実装不要）

| ファイル | 変更 |
|---|---|
| `tools/train.py` / `play_ai.py` / `godot_launcher.py` / `serve_web.py` | **変更不要**。観測次元も行動次元も Godot 側から渡るので自動追従する |
| `game/scripts/boot.gd` | 変更不要 |
| `game/scripts/train.gd` | アリーナを並べる処理は同じ。`ARENA_SCENE` の差し替えのみ |
| `game/scripts/world_view.gd` | **カメラ追従だけ要変更**（§4 参照） |
| `game/addons/godot_rl_agents/` | 変更不要 |
| `game/export_presets.cfg` | 変更不要 |

## 3. 新規に作るもの

Ball Collector と 1 対 1 で対応する。既存ファイルを読んでから書くこと。

| 新規ファイル | 役割 | 対応する既存ファイル |
|---|---|---|
| `scenes/drone.tscn` + `scripts/drone.gd` | 機体の物理制御 | `player.tscn` / `player.gd` |
| `scenes/gate.tscn` + `scripts/gate.gd` | くぐるリング | `target.tscn` / `target.gd` |
| `scenes/course.tscn` + `scripts/course.gd` | コース生成・報酬・エピソード管理 | `arena.tscn` / `arena.gd` |
| `scripts/drone_ai_controller.gd` | 観測・行動・報酬の定義 | `ball_ai_controller.gd` |

人間プレイ用シーン（`play.tscn` 相当）も新規に作るか、既存を切り替え式にする。

---

## 4. 最重要の設計上の注意点

**Ball Collector とは制御の座標系が違う。ここを間違えると人間プレイと AI 学習がズレる。**

- Ball Collector: **ワールド座標系**で制御し、カメラの回転を固定した。
  そのため「画面奥 = ワールド -Z = W キー」が常に成立していた。
- Fly By: 機体の**ローカル座標系**で制御する（機首方向が基準）。
  したがって **カメラは機体の向きに合わせて回転させる必要がある**
  （`world_view.gd` の `follow()` は回転固定なので、ここを機体追従に書き換える）。
- 同じ理由で、**観測もすべて機体ローカル座標に変換して渡すこと**。
  ワールド座標のまま渡すと、同じ状況でも機体の向き次第で観測が変わり、学習が難しくなる。

---

## 5. 段階的に作る（いきなり 6 自由度にしない）

姿勢制御を全部入れると収束が遅い。3 段階に分け、**段階 1 が動いてから次へ進むこと。**

1. **前進速度は一定、ピッチとヨーだけ操作** — 行動 2 次元。
   Ball Collector と同程度の速さで収束するはず。まずここまでを動かす。
2. スロットルを追加 — 行動 3 次元。
3. ロール + トルクによる本格的な姿勢制御 — 行動 4 次元。ここまで来ると収束は 30 分〜。

## 6. 観測（段階 1 の案、17 次元）

すべて機体ローカル座標系・正規化済み（`clampf` で ±1 に収めること）。

| 要素 | 次元 |
|---|---|
| 自機速度（ローカル） | 3 |
| 次のゲートへの相対位置（ローカル） | 3 |
| 次のゲートの法線（ローカル）— どちら向きにくぐるべきか | 3 |
| その次のゲートへの相対位置（ローカル） | 3 |
| ワールド上方向を機体ローカルで見たベクトル — 姿勢の手がかり | 3 |
| 次のゲートまでの距離 | 1 |
| 残り時間 | 1 |

**残り時間は必ず入れること。** 固定長エピソードを MDP として完結させるために要る。
これが無いと「あと何秒あるか」が分からず価値関数が正しく学習できない（Ball Collector で確認済み）。

障害物を置くなら、プラグイン同梱の `addons/godot_rl_agents/sensors/sensors_3d/RaycastSensor3D.tscn`
を機体に付けて観測に足す（公式 Fly By と同じ手法）。

## 7. 報酬

| 事象 | 報酬 |
|---|---|
| ゲート通過 | +1.0 |
| 墜落・コース外 | -1.0 |
| 次のゲートに近づく | 近づいた距離 × 0.02 |

Ball Collector で距離シェーピングが学習の立ち上がりに決定的に効いた（無いと序盤ほぼ学習しない）。

**シェーピングの落とし穴**: ゲート通過やリスポーンの直後は「次の目標」が切り替わって距離が飛ぶ。
そのタイミングで `_prev_dist` を必ず再計算すること（`arena.gd` の `_on_target_collected` / `_respawn_player` が実例）。

ゲート通過は「Area3D の `body_entered` + 進行方向が法線と同じ向き」で判定する
（逆走してくぐったのを数えないため）。

## 8. エピソード設計

Ball Collector と同じく **`AIController.reset_after` を唯一の基準**にする
（`drone.tscn` の AIController に設定）。これで人間プレイと AI 学習のエピソード長が必ず一致する。

- 60 physics tick = 1 ゲーム秒。`reset_after = 3600` で 60 秒。
- `course.gd` の `_physics_process` で `_ai.needs_reset` を見て、`_ai.done = true` → `_ai.reset()` → コース再生成。
- 人間プレイ側は `auto_reset = false` にして結果表示で止める（`arena.gd` に実装済みの形をそのまま真似る）。

---

## 9. 踏んだ地雷（同じ穴に落ちないこと）

### godot_rl 0.8.1 のバグ 2 件 — `tools/godot_launcher.py` で回避済み

1. **`GodotEnv.step_recv()` が Godot から届いた `info` を読み捨てる。**
   `[{}] * len(done)` を返す実装になっている。そのため `AIController.get_info()` の値が Python に届かない。
   → `InfoGodotEnv` で `step_recv` を差し替えて解決済み。**この対策を消さないこと。**
   これが無いと「1エピソードに何個くぐれたか」を学習ログに出せず、上達しているか判断できない。
2. **`StableBaselinesGodotEnv` が実行ファイル無しでの `n_parallel > 1` を禁止している。**
   → `LocalGodotVecEnv` で自前にプロセスを起動して回避済み。
   なお `GodotEnv` は bind と accept を同時に行うので、**「1 プロセス起動 → 接続確立 → 次を起動」と直列化が必須**。
   先に全部起動すると、まだ listen していないポートへの接続が拒否されて human モードにフォールバックし、ハングする。

### その他

- **`godot --headless --path game --import` は 2 回実行が必要な場合がある。**
  1 回目は `icon.png` の import 未生成でプラグインスクリプトがパースエラーになる。
- **`_ready()` 内での `change_scene_to_file()` は直接呼ばない。** `call_deferred` で 1 フレーム遅らせる
  （`boot.gd` 参照）。直接呼ぶとシーンツリーの子操作と衝突してエラーになる。
- **RigidBody3D の瞬間移動は `global_position` 代入では不確実。**
  `PhysicsServer3D.body_set_state()` を使う（`player.gd` の `teleport()` が実例）。
- **Godot 標準フォントは日本語グリフを持たない。** HUD の文字は必ず ASCII にする。
- **ONNX エクスポートには 2 つの回避が要る**（`train.py` に実装済み）。
  `gymnasium.vector.utils.spaces` の shim と、`onnxscript` パッケージ。
- **Godot 内での ONNX 推論はできない。** プラグインの推論部は C# 実装で、この環境は非 .NET ビルド。
  AI のプレイは「Python が推論し、Godot が描画する」構成になる（`play_ai.py`）。

### 環境の制約

- **X11 転送は遅い。** コンテナ内で `godot --path game` すると約 25fps しか出ない。
  原因はソフトウェア描画ではなく X11 のフレームバッファ転送（ローカル Xvfb なら 65fps 出る）。
  **人間が遊ぶときは Web エクスポート（ブラウザ）を使うこと。**
- **エクスポートテンプレート（1.9GB）はコンテナ再ビルドで消える。** 再取得は README の §7 参照。
- 音は出ない（オーディオデバイス無し）。CUDA も無い（CPU 学習）。

---

## 10. 有効だった実装・検証の順序

**この順序を守ること。** Ball Collector ではこれで手戻りゼロだった。

1. `godot --headless --path game --import` — パースエラーを潰す
2. `godot --headless --path game --quit-after 400` — 実行時エラーを潰す
3. **手書きの貪欲方策で基準値を取る**（次のゲートへ向かうだけの方策を Python で書き、スコアを測る）。
   Ball Collector では 36 個だった。**これが無いと「AI が上手いのか下手なのか」を判断できない。**
   同時に観測・行動の向きが正しいかの検証にもなる（符号ミスはここで露見する）。
4. 短い学習（2万ステップ）で配線を確認
5. 本番の学習（30万ステップ）

**見た目の確認方法**（ユーザーの画面にウィンドウを出さずに済む）:

人間プレイ用シーンを継承した使い捨てシーンを自作し、N フレーム後に PNG を保存して `Read` ツールで見る。
確認が済んだら消すこと。

```gdscript
# game/scripts/_shot.gd （使い捨て。play.gd 相当を継承する）
extends "res://scripts/play.gd"
var _n := 0
func _process(delta: float) -> void:
	super._process(delta)
	_n += 1
	if _n == 100:
		get_viewport().get_texture().get_image().save_png("/tmp/shot.png")
		get_tree().quit()
```

```bash
xvfb-run -s "-screen 0 1280x720x24" godot --path game res://scenes/_shot.tscn --resolution 1152x648
```

`xvfb-run` を使うのは、X11 転送だと遅いうえユーザーの画面にウィンドウが出てしまうため。

## 11. 参考: 効いたパラメータ

**PPO**（`train.py`）— そのまま流用してよい:
`MultiInputPolicy`, `n_steps=64`, `batch_size=256`, `n_epochs=10`, `lr=3e-4`,
`gamma=0.99`, `gae_lambda=0.95`, `ent_coef=0.001`, `device="cpu"`

**学習スループット**（実測）:

| 構成 | エージェント数 | steps/s |
|---|---|---|
| 16 アリーナ × 1 プロセス, speedup 8 | 16 | 960 |
| 32 × 1, speedup 40 | 32 | 4,625 |
| **16 × 3, speedup 40（既定値）** | **48** | **6,779** |
| 16 × 4, speedup 60 | 64 | 8,815 |

PPO の勾配計算込みの実効速度は約 2,500 steps/s。30万ステップで約 2 分。
`speedup` が物理 tick 上限を決める（`speedup × 60` tick/s）。遅いと感じたらまずここを上げる。

**Ball Collector の物理**（ドローンでは作り直すが、スケール感の参考に）:
重力 24（`project.godot`）、トルク 14、`linear_damp` 0.8、`angular_damp` 0.2、摩擦 1.0、最大速度 14、フィールド 30×30。

---

## 12. 完了の判定

- [ ] 人間がブラウザでプレイでき、ゲートをくぐるとスコアが増える
- [ ] 手書きの貪欲方策で基準値が取れている
- [ ] PPO の学習ログで `targets/episode` が単調に上がり、貪欲方策を上回る
- [ ] `python tools/play_ai.py` で学習済み AI のプレイが見られる
- [ ] README を更新（新ゲームの遊び方・実測値・制約）
