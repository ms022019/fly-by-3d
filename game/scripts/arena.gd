extends Node3D
## 1 プレイ分のフィールド。人間プレイでは 1 個、学習では複数個を並べて使う。
##
## エピソード管理 (60 秒 = 3600 physics tick) は AIController の
## n_steps / reset_after を唯一の基準にしている。これにより
## 人間プレイと AI 学習でエピソード長が必ず一致する。

signal score_changed(score: int)
signal episode_finished(score: int)

const TARGET_SCENE := preload("res://scenes/target.tscn")

const FALL_Y := -8.0
const TARGET_Y := 1.4
const SPAWN_Y := 1.2
const EDGE_MARGIN := 2.5

@export var arena_size := 30.0
@export var target_count := 6
## true: エピソード終了で即座に次を開始 (学習用) / false: 停止して結果表示 (人間プレイ用)
@export var auto_reset := true

@export_group("Reward")
@export var reward_collect := 1.0
@export var reward_fall := -1.0
## ターゲットに近づいた距離に比例して与える微小報酬。学習の立ち上がりを速くする。
@export var reward_approach_scale := 0.02

var player: RigidBody3D
var targets: Array = []
var score := 0
var running := true

var _ai
var _prev_dist := -1.0


func _ready() -> void:
	player = $Player
	player.arena = self
	_ai = player.ai
	_resize_platform()
	_build_edge_rails()
	_spawn_targets()
	reset_episode()


func _physics_process(_delta: float) -> void:
	if not running:
		return

	# 場外落下
	if to_local(player.global_position).y < FALL_Y:
		_ai.reward += reward_fall
		_respawn_player()
		_prev_dist = _nearest_distance()

	# 距離シェーピング (近づいた分だけ加点 / 遠ざかれば減点)
	var dist := _nearest_distance()
	if _prev_dist >= 0.0:
		_ai.reward += clampf(_prev_dist - dist, -1.0, 1.0) * reward_approach_scale
	_prev_dist = dist

	# エピソード終了 (AIController が reset_after tick 到達で needs_reset を立てる)
	if _ai.needs_reset:
		var final_score := score
		_ai.done = true
		_ai.reset()
		if auto_reset:
			reset_episode()
		else:
			running = false
			player.freeze = true
		episode_finished.emit(final_score)


func reset_episode() -> void:
	score = 0
	running = true
	player.freeze = false
	_ai.reset()
	_respawn_player()
	for t in targets:
		t.position = _random_spot()
	_prev_dist = _nearest_distance()
	score_changed.emit(score)


## 残り時間の割合 [0, 1]
func time_left_ratio() -> float:
	if _ai.reset_after <= 0:
		return 1.0
	return clampf(1.0 - float(_ai.n_steps) / float(_ai.reset_after), 0.0, 1.0)


## 残り秒数 (物理 60tick = 1 ゲーム秒)
func time_left_seconds() -> float:
	return maxf(float(_ai.reset_after - _ai.n_steps) / 60.0, 0.0)


## 指定地点から見た各ターゲットへの相対ベクトルを、近い順に返す。
func sorted_target_offsets(from_global: Vector3) -> Array:
	var offsets: Array = []
	for t in targets:
		offsets.append(t.global_position - from_global)
	offsets.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	return offsets


func _nearest_distance() -> float:
	var best := INF
	for t in targets:
		best = minf(best, t.global_position.distance_to(player.global_position))
	return 0.0 if best == INF else best


func _spawn_targets() -> void:
	var holder := $Targets
	for i in target_count:
		var t := TARGET_SCENE.instantiate()
		holder.add_child(t)
		t.collected.connect(_on_target_collected)
		targets.append(t)


func _on_target_collected(t: Node3D) -> void:
	if not running:
		return
	score += 1
	_ai.reward += reward_collect
	t.position = _random_spot_away_from(to_local(player.global_position))
	_prev_dist = _nearest_distance()
	score_changed.emit(score)


func _respawn_player() -> void:
	player.teleport(global_position + Vector3(0.0, SPAWN_Y, 0.0))


func _random_spot() -> Vector3:
	var h := arena_size * 0.5 - EDGE_MARGIN
	return Vector3(randf_range(-h, h), TARGET_Y, randf_range(-h, h))


## 再出現直後に即取得されるのを避けるため、プレイヤーから一定距離を空ける。
func _random_spot_away_from(local_pos: Vector3) -> Vector3:
	for i in 12:
		var spot := _random_spot()
		if spot.distance_to(local_pos) > 6.0:
			return spot
	return _random_spot()


## 床の見た目と当たり判定を arena_size に合わせる (サイズの定義を 1 箇所に保つ)
func _resize_platform() -> void:
	var mesh_node: MeshInstance3D = $Platform/Mesh
	var box_mesh: BoxMesh = mesh_node.mesh
	box_mesh.size = Vector3(arena_size, 1.0, arena_size)
	var col_node: CollisionShape3D = $Platform/Collision
	var box_shape: BoxShape3D = col_node.shape
	box_shape.size = Vector3(arena_size, 1.0, arena_size)


## 落下する縁が見えるように、当たり判定のない視覚的なフチを置く (学習時は不要)
func _build_edge_rails() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var half := arena_size * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.35, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.2, 0.3)
	mat.emission_energy_multiplier = 0.8
	for i in 4:
		var rail := MeshInstance3D.new()
		var m := BoxMesh.new()
		var horizontal := i < 2
		m.size = Vector3(arena_size, 0.28, 0.4) if horizontal else Vector3(0.4, 0.28, arena_size)
		m.material = mat
		rail.mesh = m
		var sign_ := 1.0 if i % 2 == 0 else -1.0
		rail.position = (
			Vector3(0.0, 0.14, sign_ * half) if horizontal else Vector3(sign_ * half, 0.14, 0.0)
		)
		add_child(rail)
