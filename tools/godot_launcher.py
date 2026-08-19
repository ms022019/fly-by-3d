"""Godot プロセスの起動と godot-rl 環境の生成をまとめたヘルパー。

エクスポートテンプレート (1.2GB) を導入していないため実行ファイルを作れない。
そこで godot-rl に「実行ファイルを起動してもらう」代わりに、こちらで
godot バイナリを直接起動し、env_path=None の GodotEnv に接続させている。
"""

from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path
from typing import List, Optional, Sequence

import numpy as np
from godot_rl.core.godot_env import GodotEnv
from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv

PROJECT_DIR = Path(__file__).resolve().parent.parent / "game"


def find_godot() -> str:
    godot = shutil.which("godot")
    if godot is None:
        raise RuntimeError("godot binary not found on PATH")
    return godot


#: 遊べるゲーム。boot.gd の GAMES と対応する。
GAMES = ("flyby", "ball")


def spawn_godot(
    *,
    port: int,
    arenas: int,
    seed: int,
    speedup: float,
    action_repeat: int,
    headless: bool,
    game: str = "flyby",
    project_dir: Path = PROJECT_DIR,
) -> subprocess.Popen:
    """学習用シーンを開いた Godot プロセスを 1 つ起動する。"""
    command: List[str] = [find_godot()]
    if headless:
        command.append("--headless")
    command += [
        "--path",
        str(project_dir),
        # boot.gd がこの 2 つを見て、どのゲームの学習シーンを開くか決める
        "--train",
        f"--game={game}",
        f"--n_arenas={arenas}",
        # 以下は addons/godot_rl_agents/sync.gd が読む引数
        f"--port={port}",
        f"--env_seed={seed}",
        f"--speedup={speedup}",
        f"--action_repeat={action_repeat}",
    ]
    return subprocess.Popen(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


class InfoGodotEnv(GodotEnv):
    """Godot が送ってくる info をそのまま Python 側へ渡す GodotEnv。

    godot_rl 0.8.1 の GodotEnv.step_recv() は、Godot が送信した "info" を読み捨てて
    空の辞書リストを返してしまう (core/godot_env.py)。sync.gd は info を正しく
    送っているので、受け取り側だけを差し替えれば AIController.get_info() の値が届く。
    これによって学習ログに「1 エピソードあたり何個取れたか」を出せる。
    """

    def step_recv(self):
        response = self._get_json_dict()
        response["obs"] = self._process_obs(response["obs"])
        done = np.array(response["done"]).tolist()
        info = response.get("info") or [{} for _ in done]
        # TODO(godot_rl): 本家 API が termination と truncation を区別したら分ける
        return response["obs"], response["reward"], done, done, info


class LocalGodotVecEnv(StableBaselinesGodotEnv):
    """自前で起動した Godot プロセス群に接続する VecEnv。

    本家 StableBaselinesGodotEnv は env_path が無い場合に n_parallel > 1 を禁止している
    (実行ファイルが無いと複数起動できないという前提のため)。ここでは自分でプロセスを
    立てるので、その制限を外している。

    GodotEnv はソケットの bind と accept を同時に行うので、
    「1 プロセス起動 → 接続確立 → 次を起動」と直列化している。
    先に全部起動すると、まだ listen していないポートへの接続が拒否されてしまう。
    """

    def __init__(
        self,
        *,
        n_parallel: int = 1,
        arenas: int = 16,
        port: int = GodotEnv.DEFAULT_PORT,
        seed: int = 0,
        speedup: float = 1.0,
        action_repeat: int = 8,
        headless: bool = True,
        game: str = "flyby",
        project_dir: Path = PROJECT_DIR,
    ) -> None:
        self.procs: List[subprocess.Popen] = []
        self.envs: List[GodotEnv] = []
        try:
            for index in range(n_parallel):
                self.procs.append(
                    spawn_godot(
                        port=port + index,
                        arenas=arenas,
                        seed=seed + index,
                        speedup=speedup,
                        action_repeat=action_repeat,
                        headless=headless,
                        game=game,
                        project_dir=project_dir,
                    )
                )
                self.envs.append(
                    InfoGodotEnv(
                        env_path=None,
                        convert_action_space=True,
                        port=port + index,
                        seed=seed + index,
                    )
                )
        except BaseException:
            self._kill_processes()
            raise

        self.n_parallel = n_parallel
        self._check_valid_action_space()
        self.results = None

    def seed(self, seed=None):
        # 本家 StableBaselinesGodotEnv は seed() が NotImplementedError を投げるが、
        # SB3 は PPO(seed=...) の初期化時にこれを呼ぶ。
        # Godot 側の乱数は起動引数 --env_seed で既に固定済みなので、ここでは何もしない。
        return [seed] * self.num_envs

    def _kill_processes(self) -> None:
        for proc in self.procs:
            if proc.poll() is None:
                proc.terminate()
        deadline = time.time() + 5.0
        for proc in self.procs:
            remaining = max(deadline - time.time(), 0.0)
            try:
                proc.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                proc.kill()
        self.procs = []

    def close(self) -> None:
        for env in self.envs:
            try:
                env.close()
            except Exception:
                pass
        self._kill_processes()
