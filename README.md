# Fly By 3D / Ball Collector 3D

Godot 4.4 + [godot-rl](https://github.com/edbeeching/godot_rl_agents) + Stable-Baselines3 で作った、
**人間も遊べて、AI も強化学習で上達する** 3D ゲーム 2 本。

同じフィールド・同じルールを、人間はキーボードで、AI は PPO で学習した方策で遊ぶ。
どちらのゲームも 60 秒のタイムアタックで、実行時の引数 (`--game`) だけで切り替わる。

**学習済み AI とその場で対戦できる。** 方策の重みをゲームに埋め込んであるので、
Python もサーバーも要らない。ブラウザを開けば AI が隣で飛んでいる (走っている)。

### ▶ ブラウザで今すぐ遊ぶ — https://ms022019.github.io/fly-by-3d/

インストール不要。`SPACE` で開始、`1`〜`4` で AI の強さ、`M` でソロ、`G` でもう一方のゲームへ。

| ゲーム | 内容 | 学習前 (ランダム) | 手書きの貪欲方策 | **PPO** |
|---|---|---|---|---|
| **Fly By** (既定) | 空中のリングを連続でくぐる | 0.0 | 34.4 | **39.6** |
| Ball Collector | 球を転がしてターゲットを集める | 0.2 | 36 | **64** |

いずれも「60 秒あたりの獲得数」。手書きの方策との比較を必ず併記しているのは、
それが無いと「AI が上手いのか下手なのか」を判断できないため。

---

## 1. 遊ぶ

### 方法 A: 公開版をブラウザで開く (いちばん手軽)

**https://ms022019.github.io/fly-by-3d/** を開くだけ。GitHub Pages で配信している。
転送されるのは gzip 圧縮後で約 9MB。

### 方法 B: 手元のビルドをブラウザで開く (改造したものを試すとき)

```bash
python tools/serve_web.py
```

VS Code がポートを転送するので、ホストの Chrome / Edge で **http://localhost:8000** を開く。
ホストの実 GPU で描画されるため滑らかに動く。起動すると Fly By が始まり、`G` キーで Ball Collector に切り替わる。

ゲームを書き換えた後は、再エクスポートが必要:

```bash
godot --headless --path game --export-release "Web" ../build/web/index.html
```

### 方法 C: Windows でネイティブ実行 (最速・音も出る)

```bash
godot --headless --path game --export-release "Windows Desktop" ../build/windows/FlyBy3D.exe
```

VS Code のエクスプローラでファイルを右クリック →「ダウンロード」でホストに取り出せる。

### 方法 D: コンテナ内で直接ウィンドウ実行 (セットアップ不要・ただし約 25fps)

```bash
godot --path game                # Fly By
godot --path game --game=ball    # Ball Collector
```

X11 転送経由なので **25fps 程度**しか出ない (理由は「9. 実測値」参照)。

### 操作

**Fly By** — 機体は常に前進する。止まることはできない。

| キー | 動作 |
|---|---|
| `SPACE` | レース開始 / やり直し |
| `W` `S` / `↑` `↓` | 機首上げ / 機首下げ |
| `A` `D` / `←` `→` | 左旋回 / 右旋回 |
| `Shift` | ブレーキ (押している間だけ減速) |
| `1` 〜 `4` | AI の強さ |
| `M` | VS AI / SOLO の切り替え |
| `R` / `G` / `Esc` | リスタート / もう一方のゲームへ / 終了 |

旋回の角速度は速度によらず一定なので、**遅く飛ぶほど小回りが利く**。
きつい曲がりの手前で `Shift` を踏むのが速く回るコツ。次にくぐるリングは黄色く光っている。
地面に激突するかコース外へ出ると復帰させられる (減点)。

**Ball Collector**

| キー | 動作 |
|---|---|
| `SPACE` | 開始 / やり直し |
| `W` `A` `S` `D` / 矢印キー | 球を転がす (画面の奥 = `W`) |
| `1` 〜 `4` | AI の強さ |
| `R` / `G` / `Esc` | リスタート / もう一方のゲームへ / 終了 |

ターゲットは共有なので、先に取った方の得点になる取り合いになる。

---

## 2. 学習済み AI と対戦する

タイトル画面で `SPACE` を押すと、学習済み AI との対戦が始まる。
**Python もサーバーも動いていない。** 方策 (obs → 64 → 64 → action の MLP) の重みを
GDScript に埋め込んであり、ゲームの中で推論している。

### 2 つのゲームで対戦の形が違う

- **Ball Collector**: 同じフィールドで**ターゲットを取り合う**。球同士がぶつかるので妨害もできる。
- **Fly By**: 同じ形のコースを 2 本、同じ座標に重ねた**ゴースト対戦**。
  相手は自分とまったく同じ経路を飛ぶので、進路の先 (か後ろ) を飛ぶ影として見える。
  当たり判定はレイヤーで分離してあり、互いのリングには反応しない。
  画面上部の「+2 gates 1.4s AHEAD」が経路上の差を示す。

順番に進む競技なので、Ball Collector と同じ「共有ターゲットの取り合い」は成立しない
(AI が先行すると人間の目標ゲートまで勝手に前へ送られてしまう)。そこでゴースト方式にしている。

### AI の強さ

方策 (ニューラルネット) は一切いじらず、**外側のパラメータだけ**を絞って 4 段階を作っている。

| レベル | Fly By (通過数/60秒) | Ball Collector (取得数/60秒) |
|---|---|---|
| `1` EASY | 15.4 | 15.3 |
| `2` NORMAL (既定) | 22.5 | 24.5 |
| `3` HARD | 28.9 | 33.7 |
| `4` FULL POWER | **39.3** | **66.5** |

絞り方はゲームで違う。Ball Collector は「トルクと速度上限を skill 倍」で足りるが、
**Fly By で同じことをすると弱くならない**。旋回の角速度が速度によらず一定なので、
遅くすると小回りが利いて逆に上手くなる。そこで Fly By は
**速度上限 (強さの天井を決める) と行動ノイズ (狙いを外させる)** の 2 つで調整している。

なお速度上限には `speed_cap` という別の変数を使っている。観測は速度を `max_speed` で
割って正規化しているので、`max_speed` 自体を下げると**手加減が観測の歪みとして方策に伝わって**しまう。

強さは自分で測り直せる (Godot ヘッドレス 1 プロセスだけなので軽い):

```bash
godot --headless --path game --bench --bench-speed-cap=9 --bench-noise=0.2   # Fly By
godot --headless --path game --bench --game=ball --bench-skill=0.35          # Ball Collector
```

### 埋め込みが正しいかの確認

Python で推論した値と、ゲーム内で推論した値が一致するかを突き合わせられる。

```bash
python tools/export_policy.py --game flyby   # 重みを書き出し、参照値を表示
godot --headless --path game --policy-probe  # ゲーム内で同じ入力を通した値を表示
```

実測では Fly By が完全一致、Ball Collector は float32 の丸め誤差のみ。
ゲーム内 AI のスコアも Python 推論の 39.6 に対して 39.3 で一致している。

---

## 3. AI を学習させる

```bash
python tools/train.py --steps 600000                  # Fly By
python tools/train.py --game ball --steps 300000      # Ball Collector
```

CPU のみで **3〜4 分**。学習の進み方がそのまま流れる (Fly By):

```
[  30,000 steps]  targets/episode   0.27  reward   -4.27  ...
[ 110,016 steps]  targets/episode  17.42  reward   24.40  ...
[ 210,000 steps]  targets/episode  34.57  reward   48.13  ...
[ 450,000 steps]  targets/episode  38.20  reward   53.30  ...
```

`models/fly_by.zip` (Ball Collector なら `models/ball_collector.zip`) に保存される。
`--resume models/fly_by.zip` で続きから学習できる。

主なオプション:

| オプション | 既定値 | 意味 |
|---|---|---|
| `--game` | `flyby` | `flyby` / `ball` |
| `--arenas` | 16 | 1 プロセス内に並べるコース数 |
| `--parallel` | 3 | Godot プロセス数 |
| `--speedup` | 40 | 物理シミュレーションの倍速 |

> **注意: 学習中は CPU を数分間フルに使う。**
> Godot ヘッドレス 3 プロセス (物理 40 倍速) と PyTorch の勾配計算が同時に走るため、
> 12 コアがほぼ 100% になり PC が熱くなる。負荷を下げたいときは
> `--parallel 1 --arenas 8 --speedup 10` にすると 1/6 程度になる (その分時間はかかる)。

## 4. AI のプレイを観る

```bash
python tools/play_ai.py                 # ウィンドウが開く
python tools/play_ai.py --headless --episodes 10    # スコアだけ測る
python tools/play_ai.py --game ball
```

## 5. 手書きの方策で基準値を取る (Fly By)

学習を一切使わず、観測から次のリングへ機首を向けるだけの方策を回す。

```bash
python tools/greedy_flyby.py --episodes 8
# -> gain  4.0  brake_at 0.90   24 episodes   mean  34.42   best  38
```

学習の良し悪しを測る物差しになるだけでなく、**観測と行動の向きが正しいかの検証**も兼ねている。
符号を間違えているとこのスコアがほぼ 0 になるので、学習を始める前に配線ミスを潰せる。

---

## 6. 公開する

GitHub Pages で配信している。**サーバー側の処理が一切ない静的ファイルだけ**なので、
置ける場所ならどこでも動く。Web ビルドはスレッドを無効にして書き出してあるため、
`COOP` / `COEP` ヘッダを立てる必要もない (立てられないホストでもそのまま動く)。

```
master     ソース一式・レポート
gh-pages   Web ビルドのみ (index.* と .nojekyll)
```

ソースとビルドをブランチで分けているので、master に 43MB のバイナリが混ざらない。
`index.wasm` は Godot のランタイムなので、ゲームを更新しても中身は変わらない
(変わるのは 188KB の `index.pck` だけ)。

ゲームを更新したときの手順:

```bash
godot --headless --path game --export-release "Web" ../build/web/index.html
git switch gh-pages
cp build/web/index.* .
git add -A && git commit -m "Web ビルドを更新" && git push
git switch master
```

push から 1 分ほどで反映される。`gh api repos/<user>/fly-by-3d/pages --jq .status` が
`built` になれば完了。

---

## 7. 構成

```
game/                        Godot プロジェクト
  scenes/
    main.tscn                起動時の入口 (引数を見て下の 4 つへ分岐)
    play_fly.tscn            Fly By / 人間プレイ
    train_fly.tscn           Fly By / 学習・AI 観戦
    play.tscn  train.tscn    Ball Collector の同じ 2 つ
    course.tscn              Fly By のコース 1 面ぶん
    drone.tscn  gate.tscn    機体 + AIController / くぐるリング
    arena.tscn player.tscn target.tscn    Ball Collector の対応物
  scripts/
    course.gd                Fly By のルール・報酬・エピソード管理
    drone.gd                 機体の物理制御 (人間入力 / AI 行動 / 埋め込み方策の 3 対応)
    gate.gd                  リングの配置と通過判定
    drone_ai_controller.gd   Fly By の観測・行動・報酬の定義 (godot-rl の規約)
    arena.gd player.gd target.gd ball_ai_controller.gd   Ball Collector の対応物
    policy.gd                埋め込んだ方策の推論 (行列積だけ。両ゲーム共用)
    policy_weights.gd        Ball Collector の重み (自動生成)
    drone_policy_weights.gd  Fly By の重み (自動生成)
    fx.gd / sfx.gd           演出と効果音 (効果音は波形を実行時生成。音声ファイル無し)
    bench.gd / bench_fly.gd  ゲーム内 AI の実力をヘッドレスで測る
    world_view.gd            カメラ・ライト・HUD (両ゲーム共用)
    boot.gd / play.gd / play_fly.gd / train.gd / screenshot.gd
  addons/godot_rl_agents/    godot-rl 公式プラグイン
tools/
  train.py                   PPO による学習
  play_ai.py                 学習済みモデルでプレイ
  greedy_flyby.py            手書きの貪欲方策で基準値を取る
  export_policy.py           学習済みモデルの重みを GDScript へ書き出す
  godot_launcher.py          Godot プロセス起動と env 生成
  serve_web.py               Web ビルドの配信
  make_report.py             Ball Collector の開発レポート (PDF) を生成
  make_report_flyby.py       Fly By の開発レポート (PDF) を生成
models/                      学習済みモデル (fly_by.zip / ball_collector.zip)
docs/
  FlyBy3D_report_ja.pdf          Fly By の開発レポート (強化学習の解説つき・12 ページ)
  BallCollector3D_report_ja.pdf  前作の開発レポート
  next_flyby.md                  Fly By を実装する際の引き継ぎメモ
spec.md                      設計時に決めたことの記録
```

### 開発レポート

作ったものと、強化学習で何をどう学習させたかを日本語でまとめた PDF が `docs/` にある。
図と実測カーブつきで、観測・行動・報酬の設計理由から PPO が内部で何をしているかまで解説してある。

```bash
python tools/make_report_flyby.py    # docs/FlyBy3D_report_ja.pdf を作り直す
```

### 人間と AI が同じゲームを遊ぶ仕組み

`drone.gd` (`player.gd`) が `AIController.heuristic` を見て入力元を切り替えるだけ。
物理・ルール・エピソード長はすべて共通のコードを通る。

```
                    ┌─ heuristic == "human" → キーボード入力
姿勢と速度の更新 ───┤
                    └─ それ以外            → Python から届いた行動
```

エピソード長 (60 秒 = 3600 physics tick) は `AIController.reset_after` を唯一の基準にしているので、
人間と AI で必ず一致する。

### 2 つのゲームで決定的に違うところ

**制御の座標系**。ここを揃えないと人間プレイと AI 学習がズレる。

- Ball Collector は**ワールド座標系**で制御し、カメラの回転を固定した。
  そのため「画面奥 = ワールド -Z = `W` キー」が常に成立する。
- Fly By は**機体ローカル座標系**で制御する (機首方向が基準)。
  したがってカメラも機体の向きに追従させ (`world_view.gd` の `follow_chase`)、
  **観測もすべて機体ローカル座標に変換して**渡している。
  ワールド座標のまま渡すと、同じ位置関係でも機首の向き次第で観測が変わり、
  「右に曲がれ」という判断を機体の向きごとに学び直すことになる。

---

## 8. AI の中身 (Fly By)

**アルゴリズム**: PPO (Stable-Baselines3) / 64×64 の 2 層 MLP / パラメータ数は数千。画像は使わない。

**観測 (17 次元、すべて機体ローカル座標系・正規化済み)**

| 要素 | 次元 |
|---|---|
| 自機速度 | 3 |
| 次のリングへの相対位置 | 3 |
| 次のリングの法線 (どちら向きにくぐるべきか) | 3 |
| その次のリングへの相対位置 (曲がる方向の先読み) | 3 |
| ワールド上方向を機体ローカルで見たベクトル (姿勢の手がかり) | 3 |
| 次のリングまでの距離 | 1 |
| 残り時間 | 1 |

残り時間を観測に含めているのは、固定長エピソードを MDP として完結させるため。
これが無いと「あと何秒あるか」が分からず、価値関数が正しく学習できない。

**行動 (連続 3 次元)**: ピッチ指令 / ヨー指令 / スロットル指令、各 `[-1, 1]`。
スロットルは速度 8〜18 m/s に対応する。

**報酬**

| 事象 | 報酬 |
|---|---|
| リング通過 | +1.0 |
| 墜落・コース外 | -1.0 |
| くぐらずに面を通り過ぎた | -0.2 |
| 次のリングに近づく | 近づいた距離 × 0.02 |

距離シェーピングが無いと、序盤に偶然リングをくぐるまで学習信号がほぼ得られない。
通過・墜落の直後は目標が切り替わって距離が飛ぶので、そのタイミングで必ず基準距離を取り直している
(ここを忘れると次のフレームに巨大な擬似報酬が出る)。

リング通過は「`Area3D` の `body_entered` + 進行方向がリングの法線と同じ向き」で判定している
(逆走してくぐったのを数えないため)。当たり判定はリングの穴だけを覆う薄い円柱で、
フレーム部分に当たり判定は無い。

**コース生成**: リングは 6 個だけ実体を作り、くぐった端から前方へ置き直してリングバッファのように使い回す。
これでコースは実質無限に伸びる。1 区間ごとに最大 42 度のヨーと 20 度のピッチでランダムに曲げ、
外周や高度の上下限に近づいたら中央へ引き戻す。

---

## 9. 実測値

この環境 (CPU 12 コア / RAM 7GB / GPU なし) で測った値。

### 学習 (Fly By, 48 エージェント = 16 コース × 3 プロセス, speedup 40)

| 経過 | steps/s |
|---|---|
| Godot 側だけ (貪欲方策を回したとき) | 約 4,200 |
| PPO の勾配計算込みの実効速度 | 約 2,950 |

60 万ステップで **約 3.4 分**。Ball Collector (行動 2 次元・観測 12 次元) は 30 万ステップ約 2 分。

構成を変えたときの Godot 側スループット (Ball Collector で計測):

| 構成 | エージェント数 | スループット |
|---|---|---|
| 16 アリーナ × 1 プロセス, speedup 8 | 16 | 960 steps/s |
| 32 × 1, speedup 40 | 32 | 4,625 steps/s |
| **16 × 3, speedup 40 (既定値)** | **48** | **6,779 steps/s** |
| 16 × 4, speedup 60 | 64 | 8,815 steps/s |

メモリは Godot ヘッドレス 1 プロセス 85MB + Python 側 672MB。

### Fly By のスコアの目安

理論上の上限は「60 秒 × 最高速 18 m/s ÷ 平均リング間隔 21.5m」でおよそ 50。
実際には曲がるぶん距離が伸びるので、40 前後がほぼ上限に近い。

| プレイヤー | 60 秒あたりの通過数 |
|---|---|
| 学習前 (ランダム) | 0.0 |
| 手書きの貪欲方策 (ブレーキ無し) | 33.0 |
| 手書きの貪欲方策 (曲がる手前で減速) | 34.4 |
| **PPO 60 万ステップ (約 3.4 分)** | **39.6** (最高 42) |

貪欲方策との差が Ball Collector ほど大きくないのは、Fly By が「次の目標へ真っ直ぐ向かう」だけで
かなりのところまで行けるタスクだから。PPO が上回っているのは主に速度の使い分けによる。

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

## 10. 制約と既知の問題

- **Godot 内での ONNX 推論はできない。**
  プラグインの推論部は C# 実装で、この環境の Godot は非 .NET (標準) ビルド。
  `addons/godot_rl_agents/onnx/wrapper/ONNX_wrapper.gd` は、誤用時に明示的なエラーを出すスタブに差し替えてある。
  `models/*.onnx` は将来 .NET ビルドへ移行したとき用に出力してある。

  ただしこの方策は obs → 64 → 64 → action の MLP (重み 5,000〜5,500 個) でしかないので、
  **重みを GDScript に埋め込んで自前で行列積を回す**ことで対戦モードは実現できている
  (`policy.gd`)。ONNX ランタイムは要らなかった。
  一方 `tools/play_ai.py` (学習直後のモデルを観る用) は今も「Python が推論し、Godot が描画する」構成。

- **音は出ない。** コンテナにオーディオデバイスが無い (Windows ネイティブビルドなら鳴る)。

- **godot_rl 0.8.1 のバグを 2 箇所回避している** (`tools/godot_launcher.py`)。
  - `GodotEnv.step_recv()` が Godot から届いた `info` を読み捨てるので、受け取り側を差し替えた。
    これが無いと「1 エピソードに何個取れたか」を Python 側で取得できない。
  - `StableBaselinesGodotEnv` が実行ファイル無しでの複数プロセス起動を禁止しているので、
    自前でプロセスを起動する形にした。なお `GodotEnv` は bind と accept を同時に行うため、
    「1 プロセス起動 → 接続確立 → 次を起動」と直列化が必須。

- **`godot --headless --path game --import` は 2 回実行が必要な場合がある。**
  1 回目は `icon.png` の import 未生成でプラグインスクリプトがパースエラーになる。

- **Godot 標準フォントは日本語グリフを持たない。** HUD の文字は ASCII に限定している。

- **エクスポートテンプレートはコンテナ再ビルドで消える。**
  `~/.local/share/godot/export_templates/4.4.stable/` (1.9GB) にあり、ここは永続化されていない。
  再ビルド後に Web / Windows ビルドを作り直すには、テンプレートの再取得が必要:

  ```bash
  curl -L -o /tmp/t.tpz https://github.com/godotengine/godot/releases/download/4.4-stable/Godot_v4.4-stable_export_templates.tpz
  mkdir -p ~/.local/share/godot/export_templates && unzip -q /tmp/t.tpz -d /tmp/tpl
  mv /tmp/tpl/templates ~/.local/share/godot/export_templates/4.4.stable
  ```

## 11. 次の一手

- **ロール + トルクによる本格的な姿勢制御**: 今の Fly By はピッチとヨーを直接指定する簡易モデルで、
  ロールは見た目だけ。角速度ではなくトルクを指令する 4 次元の行動にすると本格的な飛行になるが、
  収束は 30 分〜かかる (`docs/next_flyby.md` の段階 3)。
- **障害物 + `RaycastSensor3D`**: プラグイン同梱のレイキャストセンサーを観測に足せば、
  コース上の障害物を避ける行動が学習できる (公式 Fly By と同じ手法)。
- **サバイバルモード**: 獲得で残り時間が回復するルール。`course.gd` / `arena.gd` の変更だけで済む。
