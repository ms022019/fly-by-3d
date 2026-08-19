"""ゲームを PPO (Stable-Baselines3) で学習させる。

例:
    python tools/train.py --steps 300000                 # Fly By (既定)
    python tools/train.py --game ball --steps 300000     # Ball Collector
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.vec_env import VecMonitor

from godot_launcher import GAMES, LocalGodotVecEnv

MODEL_DIR = Path(__file__).resolve().parent.parent / "models"
#: ゲームごとの既定の保存先 (拡張子なし)
MODEL_NAMES = {"flyby": "fly_by", "ball": "ball_collector"}


class ProgressReporter(BaseCallback):
    """「AI が上達しているか」を人間が読める形で出す。

    報酬は距離シェーピングを含むので直感的でない。そこで Godot の get_info() が
    返す score (取得したターゲット数 / くぐったゲート数) を集計して一緒に表示する。
    score はエピソード内で単調増加するため、最大値がそのまま最終スコアになる。
    """

    def __init__(self, report_every: int = 10_000) -> None:
        super().__init__()
        self.report_every = report_every
        self._next_report = report_every
        self._peak: np.ndarray | None = None
        self._finished_scores: list[int] = []
        self._episode_returns: list[float] = []
        self._start = time.time()

    def _on_training_start(self) -> None:
        self._peak = np.zeros(self.training_env.num_envs, dtype=np.int64)
        self._start = time.time()

    def _on_step(self) -> bool:
        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones", [])
        for i, info in enumerate(infos):
            score = info.get("score")
            if score is not None:
                self._peak[i] = max(self._peak[i], int(score))
            if i < len(dones) and dones[i]:
                self._finished_scores.append(int(self._peak[i]))
                self._peak[i] = 0
                episode = info.get("episode")
                if episode is not None:
                    self._episode_returns.append(float(episode["r"]))

        if self.num_timesteps >= self._next_report:
            self._next_report += self.report_every
            self._log()
        return True

    def _log(self) -> None:
        elapsed = time.time() - self._start
        fps = self.num_timesteps / elapsed if elapsed > 0 else 0.0
        recent_scores = self._finished_scores[-100:]
        recent_returns = self._episode_returns[-100:]
        score_text = f"{np.mean(recent_scores):6.2f}" if recent_scores else "   n/a"
        return_text = f"{np.mean(recent_returns):7.2f}" if recent_returns else "    n/a"
        print(
            f"[{self.num_timesteps:>8,} steps]"
            f"  targets/episode {score_text}"
            f"  reward {return_text}"
            f"  episodes {len(self._finished_scores):>5}"
            f"  {fps:6.0f} steps/s"
            f"  {elapsed / 60:5.1f} min",
            flush=True,
        )

    def _on_training_end(self) -> None:
        self._log()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", choices=GAMES, default="flyby", help="どのゲームを学習するか")
    parser.add_argument("--steps", type=int, default=300_000, help="学習ステップ数")
    parser.add_argument("--arenas", type=int, default=16, help="1 プロセス内のアリーナ数")
    parser.add_argument("--parallel", type=int, default=3, help="Godot プロセス数")
    parser.add_argument("--speedup", type=float, default=40.0, help="物理を何倍速で回すか")
    parser.add_argument("--action-repeat", type=int, default=8)
    parser.add_argument("--port", type=int, default=11008)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out", type=Path, default=None, help="保存先 (既定はゲーム名から決める)")
    parser.add_argument("--resume", type=Path, default=None, help="学習を再開する .zip")
    args = parser.parse_args()
    if args.out is None:
        args.out = MODEL_DIR / MODEL_NAMES[args.game]

    env = LocalGodotVecEnv(
        n_parallel=args.parallel,
        arenas=args.arenas,
        port=args.port,
        seed=args.seed,
        speedup=args.speedup,
        action_repeat=args.action_repeat,
        headless=True,
        game=args.game,
    )
    env = VecMonitor(env)
    print(f"game = {args.game}")
    print(f"agents = {env.num_envs}  (arenas {args.arenas} x processes {args.parallel})")
    print(f"observation space: {env.observation_space}")
    print(f"action space:      {env.action_space}", flush=True)

    model = None
    try:
        if args.resume is not None:
            model = PPO.load(args.resume, env=env, device="cpu")
            print(f"resumed from {args.resume}")
        else:
            model = PPO(
                "MultiInputPolicy",
                env,
                n_steps=64,
                batch_size=256,
                n_epochs=10,
                learning_rate=3e-4,
                gamma=0.99,
                gae_lambda=0.95,
                ent_coef=0.001,
                clip_range=0.2,
                verbose=0,
                device="cpu",
                seed=args.seed,
            )

        model.learn(total_timesteps=args.steps, callback=ProgressReporter(), progress_bar=False)
    except KeyboardInterrupt:
        print("\ninterrupted - saving current model", flush=True)
    finally:
        # モデル構築前に落ちた場合は保存するものが無い
        if model is not None:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            model.save(args.out)
            print(f"saved {args.out}.zip")
            _try_export_onnx(model, args.out.with_suffix(".onnx"))
        env.close()


def _try_export_onnx(model: PPO, path: Path) -> None:
    """将来 Godot .NET ビルドへ移行したときのために ONNX も出しておく。

    現在の非 .NET ビルドでは Godot 側で読み込めないので、失敗しても学習結果は失わない。
    """
    try:
        # godot_rl 0.8.1 のエクスポータは gymnasium.vector.utils.spaces を import するが、
        # gymnasium 1.x でこの再エクスポートが無くなっている。読み込めるよう補う。
        import gymnasium
        import gymnasium.vector.utils as vector_utils

        if not hasattr(vector_utils, "spaces"):
            vector_utils.spaces = gymnasium.spaces

        from godot_rl.wrappers.onnx.stable_baselines_export import export_ppo_model_as_onnx

        export_ppo_model_as_onnx(model, str(path))
        print(f"saved {path}")
    except Exception as exc:  # noqa: BLE001
        print(f"(onnx export skipped: {exc})")


if __name__ == "__main__":
    main()
