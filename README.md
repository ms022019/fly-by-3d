# Ball Collector 3D

Godot 4.4 + [godot-rl](https://github.com/edbeeching/godot_rl_agents) + Stable-Baselines3 で作った、
**人間も遊べて、AI も強化学習で上達する** 3D ゲーム。

球体を転がして 60 秒でターゲットを何個集められるかを競う。
同じフィールド・同じルールを、人間はキーボードで、AI は PPO で学習した方策で遊ぶ。

| プレイヤー | 60 秒あたりの取得数 |
|---|---|
| 学習前の AI (ランダム) | 0.2 |
| 手書きの貪欲方策 (最寄りへ直進するだけ) | 36 |
| **PPO で 18 万ステップ学習した AI** | **64** |

---

## 1. 遊ぶ

### 方法 A: ブラウザ (推奨・いちばん滑らか)

```bash
python tools/serve_web.py
```

VS Code がポートを転送するので、ホストの Chrome / Edge で **http://localhost:8000** を開く。
ホストの実 GPU で描画されるため滑らかに動く。

ゲームを書き換えた後は、再エクスポートが必要:

```bash
godot --headless --path game --export-release "Web" ../build/web/index.html
```

### 方法 B: Windows でネイティブ実行 (最速・音も出る)

`build/windows/BallCollector3D.exe` を Windows 側にコピーして実行する。
VS Code のエクスプローラでファイルを右クリック →「ダウンロード」でホストに取り出せる。

### 方法 C: コンテナ内で直接ウィンドウ実行 (セットアップ不要・ただし約 25fps)

```bash
godot --path game
```

X11 転送経由なので **25fps 程度**しか出ない (理由は「6. 実測値」参照)。
動作確認には十分だが、快適に遊ぶなら A か B を使う。

### 操作

| キー | 動作 |
|---|---|
| `W` `A` `S` `D` / 矢印キー | 球を転がす (画面の奥 = `W`) |
| `R` | リスタート |
| `Esc` | 終了 |

慣性で滑るので、止まりたい方向と逆に入力して減速する。

---

## 2. AI を学習させる

```bash
python tools/train.py --steps 300000
```

CPU のみで **約 2 分**。学習の進み方がそのまま流れる:

```
[  10,032 steps]  targets/episode   0.17  reward    0.17  ...
[  50,016 steps]  targets/episode  21.89  reward   23.13  ...
[  90,000 steps]  targets/episode  50.54  reward   55.34  ...
[ 180,000 steps]  targets/episode  62.29  reward   68.17  ...
```

`models/ball_collector.zip` に保存される。`--resume models/ball_collector.zip` で続きから学習できる。

主なオプション:

| オプション | 既定値 | 意味 |
|---|---|---|
| `--arenas` | 16 | 1 プロセス内に並べるアリーナ数 |
| `--parallel` | 3 | Godot プロセス数 |
| `--speedup` | 40 | 物理シミュレーションの倍速 |

## 3. AI のプレイを観る

```bash
python tools/play_ai.py
```

ウィンドウが開き、学習済み AI がプレイする様子が見られる。
スコアだけ測りたいときは `--headless` を付ける。

```bash
python tools/play_ai.py --headless --episodes 10
```

---

## 4. 構成

```
game/                        Godot プロジェクト
  scenes/
    main.tscn                起動時の入口 (引数を見て下の 2 つへ分岐)
    play.tscn                人間がプレイするシーン
    train.tscn               学習 / AI 観戦シーン (アリーナを複数並べる)
    arena.tscn               フィールド 1 面ぶん
    player.tscn              球体プレイヤー + AIController
    target.tscn              集めるターゲット
  scripts/
    arena.gd                 ルール・報酬・エピソード管理
    player.gd                球の物理制御 (人間入力 / AI 行動の両対応)
    ball_ai_controller.gd    観測・行動・報酬の定義 (godot-rl の規約)
    world_view.gd            カメラ・ライト・HUD
    boot.gd / play.gd / train.gd
  addons/godot_rl_agents/    godot-rl 公式プラグイン
tools/
  train.py                   PPO による学習
  play_ai.py                 学習済みモデルでプレイ
  godot_launcher.py          Godot プロセス起動と env 生成
  serve_web.py               Web ビルドの配信
models/                      学習済みモデル
spec.md                      設計時に決めたことの記録
```

### 人間と AI が同じゲームを遊ぶ仕組み

`player.gd` が `AIController.heuristic` を見て入力元を切り替えるだけ。
物理・ルール・エピソード長はすべて共通のコードを通る。

```
              ┌─ heuristic == "human" → キーボード入力
apply_torque ─┤
              └─ それ以外            → Python から届いた行動
```

エピソード長 (60 秒 = 3600 physics tick) は `AIController.reset_after` を唯一の基準にしているので、
人間と AI で必ず一致する。

---

## 5. AI の中身

**アルゴリズム**: PPO (Stable-Baselines3) / 64×64 の 2 層 MLP / パラメータ数は数千。画像は使わない。

**観測 (12 次元、すべて正規化済み)**

| 要素 | 次元 |
|---|---|
| 自分の速度 x, y, z | 3 |
| アリーナ内での自分の位置 x, y, z | 3 |
| 最寄りターゲットへの相対位置 x, z | 2 |
| 2 番目に近いターゲットへの相対位置 x, z | 2 |
| 最寄りターゲットまでの距離 | 1 |
| 残り時間 | 1 |

残り時間を観測に含めているのは、固定長エピソードを MDP として完結させるため。
これが無いと「あと何秒あるか」が分からず、価値関数が正しく学習できない。

**行動 (連続 2 次元)**: ワールド X / Z 方向のトルク指令、各 `[-1, 1]`。

**報酬**

| 事象 | 報酬 |
|---|---|
| ターゲット取得 | +1.0 |
| 場外落下 | -1.0 |
| ターゲットに近づく | 近づいた距離 × 0.02 |

距離シェーピングが無いと、序盤にターゲットへ偶然触れるまで学習信号がほぼ得られない。

---

## 6. 実測値

この環境 (CPU 12 コア / RAM 7GB / GPU なし) で測った値。

### 学習

| 構成 | エージェント数 | スループット |
|---|---|---|
| 16 アリーナ × 1 プロセス, speedup 8 | 16 | 960 steps/s |
| 32 × 1, speedup 40 | 32 | 4,625 steps/s |
| **16 × 3, speedup 40 (既定値)** | **48** | **6,779 steps/s** |
| 16 × 4, speedup 60 | 64 | 8,815 steps/s |

PPO の勾配計算を含めた実効速度は約 2,500 steps/s。30 万ステップで約 2 分。
メモリは Godot ヘッドレス 1 プロセス 85MB + Python 側 672MB。

### 描画

| 条件 | FPS |
|---|---|
| ローカル Xvfb (転送なし)、1152×648 | **65.3** |
| X11 転送 (VS Code 経由)、1152×648 | 12.0 |
| X11 転送、640×360 | 24.2 |
| X11 転送、512×288 | 25.4 |

**ソフトウェア描画 (llvmpipe) は 65fps 出ており、遅いのは X11 のフレームバッファ転送**。
解像度を下げても 25fps で頭打ちになる (帯域ではなく往復レイテンシが固定コストのため)。
だからブラウザ / ネイティブでのプレイを推奨している。

---

## 7. 制約と既知の問題

- **Godot 内での ONNX 推論はできない。**
  プラグインの推論部は C# 実装で、この環境の Godot は非 .NET (標準) ビルド。
  そのため AI のプレイは「Python が推論し、Godot が描画する」構成になっている。
  `addons/godot_rl_agents/onnx/wrapper/ONNX_wrapper.gd` は、誤用時に明示的なエラーを出すスタブに差し替えてある。
  `models/ball_collector.onnx` は将来 .NET ビルドへ移行したとき用に出力してある。

- **音は出ない。** コンテナにオーディオデバイスが無い (Windows ネイティブビルドなら鳴る)。

- **godot_rl 0.8.1 のバグを 2 箇所回避している** (`tools/godot_launcher.py`)。
  - `GodotEnv.step_recv()` が Godot から届いた `info` を読み捨てるので、受け取り側を差し替えた。
    これが無いと「1 エピソードに何個取れたか」を Python 側で取得できない。
  - `StableBaselinesGodotEnv` が実行ファイル無しでの複数プロセス起動を禁止しているので、
    自前でプロセスを起動する形にした。

- **エクスポートテンプレートはコンテナ再ビルドで消える。**
  `~/.local/share/godot/export_templates/4.4.stable/` (1.9GB) にあり、ここは永続化されていない。
  再ビルド後に Web / Windows ビルドを作り直すには、テンプレートの再取得が必要:

  ```bash
  curl -L -o /tmp/t.tpz https://github.com/godotengine/godot/releases/download/4.4-stable/Godot_v4.4-stable_export_templates.tpz
  mkdir -p ~/.local/share/godot/export_templates && unzip -q /tmp/t.tpz -d /tmp/tpl
  mv /tmp/tpl/templates ~/.local/share/godot/export_templates/4.4.stable
  ```

## 8. 次の一手

- **障害物 + `RaycastSensor3D`**: 今のフィールドは平坦で、AI は周囲を見ていない。
  プラグインに同梱のレイキャストセンサーを観測に足せば、障害物を避ける行動が学習できる。
- **Fly By 風ゲートくぐり**: 空中のリングを連続でくぐる 3D タスク。
  観測・行動・報酬の骨組みはそのまま流用できる。
- **サバイバルモード**: ターゲット取得で残り時間が回復するルール。`arena.gd` の変更だけで済む。
