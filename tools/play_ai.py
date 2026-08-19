"""学習済みモデルにゲームをプレイさせ、その様子をウィンドウで観る。

この環境の Godot は非 .NET ビルドで、プラグインの ONNX 推論部 (C# 実装) が使えない。
そのため Godot 単体で学習済みモデルを動かすことはできず、
「Python が方策を推論し、Godot が描画する」という構成になる。

例:
    python tools/play_ai.py                  # Fly By (既定)
    python tools/play_ai.py --game ball      # Ball Collector
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from stable_baselines3 import PPO

from godot_launcher import GAMES, LocalGodotVecEnv

MODEL_DIR = Path(__file__).resolve().parent.parent / "models"
MODEL_NAMES = {"flyby": "fly_by", "ball": "ball_collector"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", choices=GAMES, default="flyby")
    parser.add_argument("--model", type=Path, default=None, help="既定はゲーム名から決める")
    parser.add_argument("--arenas", type=int, default=1, help="同時に見せるアリーナ数")
    parser.add_argument("--episodes", type=int, default=3)
    parser.add_argument("--port", type=int, default=11020)
    parser.add_argument("--speedup", type=float, default=1.0, help="1.0 = 等速で観る")
    parser.add_argument("--action-repeat", type=int, default=8)
    parser.add_argument("--headless", action="store_true", help="描画せずスコアだけ測る")
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="方策からサンプリングする (既定は決定論的に最頻行動を選ぶ)",
    )
    args = parser.parse_args()
    if args.model is None:
        args.model = MODEL_DIR / f"{MODEL_NAMES[args.game]}.zip"

    if not args.model.exists():
        raise SystemExit(f"model not found: {args.model}\nRun tools/train.py first.")

    env = LocalGodotVecEnv(
        n_parallel=1,
        arenas=args.arenas,
        port=args.port,
        seed=0,
        speedup=args.speedup,
        action_repeat=args.action_repeat,
        headless=args.headless,
        game=args.game,
    )
    model = PPO.load(args.model, device="cpu")

    peak = np.zeros(env.num_envs, dtype=np.int64)
    # env.reset() は Godot 側のエピソード境界とは揃わないため、
    # 各環境の最初の 1 エピソードは途中から始まった不完全なもの。集計から除く。
    warmed_up = np.zeros(env.num_envs, dtype=bool)
    finished: list[int] = []
    obs = env.reset()
    try:
        while len(finished) < args.episodes * env.num_envs:
            action, _ = model.predict(obs, deterministic=not args.stochastic)
            obs, _reward, dones, infos = env.step(action)
            for i, info in enumerate(infos):
                score = info.get("score")
                if score is not None:
                    peak[i] = max(peak[i], int(score))
                if dones[i]:
                    if warmed_up[i]:
                        finished.append(int(peak[i]))
                        print(f"episode {len(finished):>3}:  {peak[i]} points", flush=True)
                    else:
                        warmed_up[i] = True
                    peak[i] = 0
    except KeyboardInterrupt:
        print("\ninterrupted")
    finally:
        env.close()

    if finished:
        print(f"\n{len(finished)} episodes   mean {np.mean(finished):.2f}   best {max(finished)}")


if __name__ == "__main__":
    main()
