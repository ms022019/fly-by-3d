extends AIController3D
## godot-rl 用のエージェント定義 (Fly By)。観測 / 行動 / 報酬をここで規定する。
##
## 観測: 17 次元。**すべて機体ローカル座標系**に変換してある。
## ワールド座標のまま渡すと、同じ位置関係でも機首の向き次第で値が変わり、
## 「右に曲がれ」という判断を機体の向きごとに学び直すことになる。
##
## 行動: 連続 3 次元 (ピッチ指令, ヨー指令, スロットル指令)。

## 相対位置・距離の正規化に使う基準距離 [m]。ゲート間隔の最大値より少し大きい。
const OBS_RANGE := 40.0

## Python から受け取った行動。Drone が毎 physics フレーム参照する。
var control := Vector3(0.0, 0.0, 1.0)


func get_obs() -> Dictionary:
	var course: Node3D = _player.course
	# ワールド → 機体ローカルへの変換 (basis は正規直交なので inverse で足りる)
	var to_local_basis: Basis = _player.global_transform.basis.inverse()
	var pos: Vector3 = _player.global_position

	var next_gate: Node3D = course.gate_at(0)
	var later_gate: Node3D = course.gate_at(1)
	var to_next: Vector3 = next_gate.global_position - pos
	var to_later: Vector3 = later_gate.global_position - pos

	# max_speed で割る (現在速度で割ると常に 1 になり、速さが観測から消える)
	var vel: Vector3 = to_local_basis * _player.linear_velocity / _player.max_speed
	var rel_next: Vector3 = to_local_basis * to_next / OBS_RANGE
	var rel_later: Vector3 = to_local_basis * to_later / OBS_RANGE
	var normal_next: Vector3 = to_local_basis * course.global_direction(next_gate.normal)
	var up: Vector3 = to_local_basis * Vector3.UP

	var obs := [
		# 自機速度 (ローカル)
		clampf(vel.x, -1.0, 1.0),
		clampf(vel.y, -1.0, 1.0),
		clampf(vel.z, -1.0, 1.0),
		# 次のゲートへの相対位置 (ローカル)
		clampf(rel_next.x, -1.0, 1.0),
		clampf(rel_next.y, -1.0, 1.0),
		clampf(rel_next.z, -1.0, 1.0),
		# 次のゲートの法線 (ローカル) — どちら向きにくぐるべきか
		normal_next.x,
		normal_next.y,
		normal_next.z,
		# その次のゲートへの相対位置 (ローカル) — 曲がる方向を先読みするため
		clampf(rel_later.x, -1.0, 1.0),
		clampf(rel_later.y, -1.0, 1.0),
		clampf(rel_later.z, -1.0, 1.0),
		# ワールド上方向を機体ローカルで見たベクトル — 姿勢の手がかり
		up.x,
		up.y,
		up.z,
		# 次のゲートまでの距離
		clampf(to_next.length() / OBS_RANGE, 0.0, 1.0),
		# 残り時間 (固定長エピソードを MDP として完結させるために必要)
		course.time_left_ratio(),
	]
	return {"obs": obs}


func get_reward() -> float:
	return reward


func get_action_space() -> Dictionary:
	return {"control": {"size": 3, "action_type": "continuous"}}


func set_action(action) -> void:
	control.x = clampf(action["control"][0], -1.0, 1.0)
	control.y = clampf(action["control"][1], -1.0, 1.0)
	control.z = clampf(action["control"][2], -1.0, 1.0)


## 専門家デモ記録モード用 (現状未使用だが AIController の規約上あると安全)
func get_action() -> Array:
	return [control.x, control.y, control.z]


## Python 側の学習ログで「何個くぐれたか」を見るために現在スコアを渡す。
## スコアはエピソード内で単調増加するので、Python 側は最大値を取れば最終スコアになる。
func get_info() -> Dictionary:
	return {"score": _player.course.score}
