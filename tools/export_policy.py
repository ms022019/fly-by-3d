"""学習済み PPO の方策ネットワークを GDScript のソースとして書き出す。

この環境の Godot は非 .NET ビルドで、godot-rl 同梱の ONNX 推論 (C# 実装) が使えない。
しかしこの方策は 12 -> 64 -> 64 -> 2 (Fly By は 17 -> 64 -> 64 -> 3) の小さな MLP でしかないので、
重みを埋め込んで GDScript 側で行列積を回す方が話が早い。こうすると
Python もサーバーも無しに、ブラウザや Windows ビルドの中で AI が動く。

    python tools/export_policy.py --game ball    -> game/scripts/policy_weights.gd
    python tools/export_policy.py --game flyby   -> game/scripts/drone_policy_weights.gd

層の形状はモデルから読むので、観測・行動の次元が違っても同じコードで書き出せる。
"""

from __future__ import annotations

import argparse
import base64
from pathlib import Path

import numpy as np
from stable_baselines3 import PPO

ROOT = Path(__file__).resolve().parent.parent
#: ゲームごとの既定値 (モデル, 出力先, GDScript の class_name)
GAMES = {
    "ball": ("ball_collector.zip", "policy_weights.gd", "PolicyWeights"),
    "flyby": ("fly_by.zip", "drone_policy_weights.gd", "DronePolicyWeights"),
}

HEADER = '''# このファイルは tools/export_policy.py が自動生成する。手で編集しない。
#
# 元: {source}  ({steps:,} steps 学習)
# 構造: obs {obs} -> Linear+tanh {hidden} -> Linear+tanh {hidden} -> Linear {act}
#
# 重みは float32 のリトルエンディアン列を base64 にしたもの。
# 行優先 (row-major) で、W[出力][入力] の順に並んでいる。
class_name {class_name}

const OBS_SIZE := {obs}
const HIDDEN := {hidden}
const ACTION_SIZE := {act}
const TRAINED_STEPS := {steps}

'''


def _b64(array: np.ndarray) -> str:
    return base64.b64encode(np.ascontiguousarray(array, dtype="<f4").tobytes()).decode("ascii")


def _wrap(text: str, width: int = 96) -> str:
    """1 行が長すぎると Godot エディタで扱いづらいので分割して連結する。"""
    chunks = [text[i : i + width] for i in range(0, len(text), width)]
    return '\n\t+ '.join(f'"{c}"' for c in chunks)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", choices=sorted(GAMES), default="flyby")
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--class-name", default=None)
    args = parser.parse_args()

    model_name, out_name, class_name = GAMES[args.game]
    if args.model is None:
        args.model = ROOT / "models" / model_name
    if args.out is None:
        args.out = ROOT / "game" / "scripts" / out_name
    if args.class_name is None:
        args.class_name = class_name

    if not args.model.exists():
        raise SystemExit(f"model not found: {args.model}\nRun tools/train.py first.")

    model = PPO.load(args.model, device="cpu")
    state = {k: v.detach().cpu().numpy() for k, v in model.policy.state_dict().items()}

    # 決定論的な行動 = 正規分布の平均 = action_net(mlp_extractor.policy_net(obs))。
    # 価値関数 (value_net) は学習中にしか使わないので持ち出さない。
    layers = [
        ("W0", state["mlp_extractor.policy_net.0.weight"]),
        ("B0", state["mlp_extractor.policy_net.0.bias"]),
        ("W1", state["mlp_extractor.policy_net.2.weight"]),
        ("B1", state["mlp_extractor.policy_net.2.bias"]),
        ("W2", state["action_net.weight"]),
        ("B2", state["action_net.bias"]),
    ]

    obs_size = layers[0][1].shape[1]
    hidden = layers[0][1].shape[0]
    act_size = layers[4][1].shape[0]

    body = HEADER.format(
        source=args.model.relative_to(ROOT).as_posix(),
        steps=int(model.num_timesteps),
        obs=obs_size,
        hidden=hidden,
        act=act_size,
        class_name=args.class_name,
    )
    for name, value in layers:
        shape = "x".join(str(d) for d in value.shape)
        body += f"\n## {name}  [{shape}]\nconst {name}_B64 := (\n\t{_wrap(_b64(value))}\n)\n"

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(body, encoding="utf-8")

    total = sum(v.size for _, v in layers)
    print(f"saved {args.out.relative_to(ROOT)}  ({total:,} weights, {len(body) / 1024:.0f} KB)")

    # 埋め込んだ重みで GDScript 実装と同じ計算を行い、参照値を出しておく。
    # これを Godot 側の出力 (godot --headless --path game --policy-probe) と突き合わせる。
    # クリップ前の生の値を出すのは、飽和で差が隠れないようにするため。
    probe = np.sin(np.arange(obs_size, dtype=np.float32)) * 0.3
    h = np.tanh(layers[0][1] @ probe + layers[1][1])
    h = np.tanh(layers[2][1] @ h + layers[3][1])
    raw = layers[4][1] @ h + layers[5][1]
    print("probe obs        :", " ".join(f"{v:+.4f}" for v in probe))
    print("probe action(raw):", " ".join(f"{v:+.6f}" for v in raw))


if __name__ == "__main__":
    main()
