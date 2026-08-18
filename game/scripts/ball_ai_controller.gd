extends AIController3D
## godot-rl 用のエージェント定義。観測 / 行動 / 報酬をここで規定する。
##
## 観測: 12 次元 (すべて概ね [-1, 1] に正規化)
## 行動: 連続 2 次元 (ワールド X/Z 方向のトルク指令)

## Python から受け取った行動。Player が毎 physics フレーム参照する。
var move := Vector2.ZERO


func get_obs() -> Dictionary:
	var arena: Node3D = _player.arena
	var half: float = arena.arena_size * 0.5
	var local_pos: Vector3 = arena.to_local(_player.global_position)
	var vel: Vector3 = _player.linear_velocity / 15.0
	var offsets: Array = arena.sorted_target_offsets(_player.global_position)
	var near1: Vector3 = offsets[0] if offsets.size() > 0 else Vector3.ZERO
	var near2: Vector3 = offsets[1] if offsets.size() > 1 else near1

	var obs := [
		# 自分の速度
		clampf(vel.x, -1.0, 1.0),
		clampf(vel.y, -1.0, 1.0),
		clampf(vel.z, -1.0, 1.0),
		# アリーナ内での自分の位置 (場外を認識できるよう ±1 を超える余地を残す)
		clampf(local_pos.x / half, -1.5, 1.5),
		clampf(local_pos.y / 10.0, -1.0, 1.0),
		clampf(local_pos.z / half, -1.5, 1.5),
		# 最寄りターゲットへの相対位置
		clampf(near1.x / half, -1.0, 1.0),
		clampf(near1.z / half, -1.0, 1.0),
		# 2 番目に近いターゲットへの相対位置 (経路取りの手がかり)
		clampf(near2.x / half, -1.0, 1.0),
		clampf(near2.z / half, -1.0, 1.0),
		# 最寄りターゲットまでの距離
		clampf(near1.length() / (half * 2.0), 0.0, 1.0),
		# 残り時間 (固定長エピソードを MDP として完結させるために必要)
		arena.time_left_ratio(),
	]
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {"move": {"size": 2, "action_type": "continuous"}}


func set_action(action) -> void:
	move.x = clampf(action["move"][0], -1.0, 1.0)
	move.y = clampf(action["move"][1], -1.0, 1.0)


## 専門家デモ記録モード用 (現状未使用だが AIController の規約上あると安全)
func get_action() -> Array:
	return [move.x, move.y]


## Python 側の学習ログで「何個取れたか」を見るために現在スコアを渡す。
## スコアはエピソード内で単調増加するので、Python 側は最大値を取れば最終スコアになる。
func get_info() -> Dictionary:
	return {"score": _player.arena.score}
