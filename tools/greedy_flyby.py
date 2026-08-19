"""Fly By の基準値を手書きの方策で測る。

「AI が上手いのか下手なのか」を判断する物差しがないと学習結果を評価できない。
そこで学習を一切使わず、観測から次のゲートの方向へ機首を向けるだけの方策を回す。

同時に観測と行動の向きが正しいかの検証にもなる。符号を間違えていれば
このスコアがほぼ 0 になるので、学習を始める前に配線ミスを潰せる。

    python tools/greedy_flyby.py --episodes 8
"""

from __future__ import annotations

import argparse

import numpy as np

from godot_launcher import LocalGodotVecEnv

# drone_ai_controller.gd の観測の並び (機体ローカル座標系)
REL_NEXT = slice(3, 6)  # 次のゲートへの相対位置
REL_LATER = slice(9, 12)  # その次のゲートへの相対位置


def greedy_action(obs: np.ndarray, gain: float, lead: float, brake_at: float) -> np.ndarray:
    """次のゲートへ機首を向ける行動を返す。

    観測はすでに機体ローカル座標系なので、相対位置の x が右方向、y が上方向、
    -z が正面方向をそのまま意味する。したがって「y が正なら機首上げ、
    x が正なら右旋回」という比例制御でよい。

    スロットルは「ゲートが正面から外れているほど緩める」。
    旋回の角速度は速度によらないので、遅く飛ぶほど小回りが利く。
    """
    aim = obs[:, REL_NEXT] + lead * obs[:, REL_LATER]
    norm = np.linalg.norm(aim, axis=1, keepdims=True)
    direction = aim / np.maximum(norm, 1e-6)
    pitch = np.clip(direction[:, 1] * gain, -1.0, 1.0)
    yaw = np.clip(direction[:, 0] * gain, -1.0, 1.0)
    # -z が正面なので、これが 1 に近いほどゲートは真正面
    ahead = -direction[:, 2]
    throttle = np.clip((ahead - brake_at) * 10.0, -1.0, 1.0)
    return np.stack([pitch, yaw, throttle], axis=1).astype(np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--episodes", type=int, default=8, help="1 エージェントあたりの回数")
    parser.add_argument("--arenas", type=int, default=8)
    parser.add_argument("--speedup", type=float, default=20.0)
    parser.add_argument("--action-repeat", type=int, default=8)
    parser.add_argument("--port", type=int, default=11040)
    parser.add_argument("--gain", type=float, default=4.0, help="旋回の強さ")
    parser.add_argument("--lead", type=float, default=0.0, help="次の次のゲートを見る度合い (実測では 0 が最良)")
    parser.add_argument(
        "--brake-at", type=float, default=0.9, help="ゲートの正面度がこれを下回ると減速する"
    )
    parser.add_argument("--render", action="store_true", help="ウィンドウを開いて眺める")
    args = parser.parse_args()

    env = LocalGodotVecEnv(
        n_parallel=1,
        arenas=args.arenas,
        port=args.port,
        seed=0,
        speedup=args.speedup,
        action_repeat=args.action_repeat,
        headless=not args.render,
        game="flyby",
    )

    peak = np.zeros(env.num_envs, dtype=np.int64)
    # env.reset() は Godot 側のエピソード境界と揃わないので、
    # 各エージェントの最初の 1 エピソードは途中から始まった不完全なもの。集計から除く。
    warmed_up = np.zeros(env.num_envs, dtype=bool)
    finished: list[int] = []
    obs = env.reset()
    try:
        while len(finished) < args.episodes * env.num_envs:
            action = greedy_action(obs["obs"], args.gain, args.lead, args.brake_at)
            obs, _reward, dones, infos = env.step(action)
            for i, info in enumerate(infos):
                score = info.get("score")
                if score is not None:
                    peak[i] = max(peak[i], int(score))
                if dones[i]:
                    if warmed_up[i]:
                        finished.append(int(peak[i]))
                    else:
                        warmed_up[i] = True
                    peak[i] = 0
    except KeyboardInterrupt:
        print("\ninterrupted")
    finally:
        env.close()

    if finished:
        print(
            f"gain {args.gain:4.1f}  brake_at {args.brake_at:4.2f}  "
            f"{len(finished):>3} episodes   "
            f"mean {np.mean(finished):6.2f}   best {max(finished):>3}"
        )


if __name__ == "__main__":
    main()
