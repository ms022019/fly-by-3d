extends Node3D
## 1 プレイ分のコース。人間プレイでは 1 個、学習では複数個を並べて使う。
##
## ゲートは GATE_COUNT 個だけ実体を作り、くぐった端から前方へ置き直して
## リングバッファのように使い回す。こうするとコースは実質無限に伸び、
## 「60 秒で何個くぐれたか」を Ball Collector と同じ基準で測れる。
##
## エピソード管理 (60 秒 = 3600 physics tick) は AIController の
## n_steps / reset_after を唯一の基準にしている。これにより
## 人間プレイと AI 学習でエピソード長が必ず一致する。
##
## VS モードでは、このコースを 2 つ同じ座標に重ねて使う。乱数シードを揃えるので
## 2 本はまったく同じ形になり、相手機は自分と同じ経路を飛ぶゴーストとして見える。
## 当たり判定は physics_layer で分離してあるので、互いのリングには反応しない。

signal score_changed(score: int)
signal episode_finished(score: int)
## 見せ方 (演出) 側に「どこでくぐったか」を伝えるための通知
signal gate_passed(at: Vector3)

const GATE_SCENE := preload("res://scenes/gate.tscn")

## 同時に存在させるゲート数 = 何個先まで見えるか
const GATE_COUNT := 6
## ゲート間隔
const GAP_MIN := 17.0
const GAP_MAX := 26.0
## コースが 1 区間で曲がる最大角
const MAX_TURN_DEG := 42.0
const MAX_CLIMB_DEG := 20.0
## ゲートを置く高度の範囲
const GATE_Y_MIN := 8.0
const GATE_Y_MAX := 28.0
const START_Y := 16.0
## 墜落・コース外の判定 (地面は y = 0、リングは半径 3 なので余裕をみる)
const CRASH_Y := 2.0
const CEILING_Y := 55.0

## コースを収める水平半径。これを超えそうになると経路を中心へ引き戻す。
@export var course_radius := 45.0
## 機体がここまで離れたら墜落扱い。地面 (180x180) の内側に収まる値にすること。
@export var out_of_bounds_radius := 70.0
## true: エピソード終了で即座に次を開始 (学習用) / false: 停止して結果表示 (人間プレイ用)
@export var auto_reset := true
## コース生成の乱数シード。VS モードでは 2 本のコースに同じ値を入れて同じ形にする。
## 0 = 毎回ランダム。学習では必ず 0 のままにすること
## (固定するとどのコースも毎エピソード同じ形になり、学習が偏る)。
@export var rng_seed := 0
## 当たり判定のレイヤー番号 (1 始まり)。VS モードでは 2 本のコースで別の番号にする。
@export var physics_layer := 1
## false にするとリングと地面を描かない (VS モードの相手側コース用)
@export var show_scenery := true
## true: 墜落してもコース形状を保ち、直前のゲートの手前へ復帰する (VS モード用)
## false: コースを作り直してスタートへ戻る (ソロ・学習用。学習時と同じ挙動)
@export var respawn_at_gate := false

@export_group("Reward")
@export var reward_pass := 1.0
@export var reward_crash := -1.0
## くぐらずに面を通り過ぎた場合。0 でも学習はするが、負にすると狙いが定まりやすい。
@export var reward_miss := -0.2
## 次のゲートに近づいた距離に比例して与える微小報酬。学習の立ち上がりを速くする。
@export var reward_approach_scale := 0.02

var player: RigidBody3D
var gates: Array = []
var score := 0
var running := true

var _ai
## gates 配列のうち「次にくぐるべきゲート」の位置
var _index := 0
## コース生成の先端 (最後に置いたゲートの位置と進行方向)
var _path_pos := Vector3.ZERO
var _path_dir := Vector3.FORWARD
var _prev_dist := -1.0
## コース生成専用の乱数。グローバル乱数を使うと 2 本のコースが揃わない。
var _rng := RandomNumberGenerator.new()
## 経路上をどれだけ進んだか [m]。VS モードで相手との差を出すのに使う。
var _travelled := 0.0
## 現在の区間 (前のゲート -> 目標ゲート) の長さ [m]
var _leg := 1.0


func _ready() -> void:
	player = $Drone
	if not show_scenery:
		$Ground.visible = false
	player.course = self
	_ai = player.ai
	_build_gates()
	_apply_physics_layer()
	_build_ground_grid()
	reset_episode()


func _physics_process(_delta: float) -> void:
	if not running:
		return

	var local := to_local(player.global_position)

	# 墜落・コース外
	if _is_out(local):
		_ai.reward += reward_crash
		if respawn_at_gate:
			_respawn_at_gate()
		else:
			_rebuild_course()
		return

	# 目標ゲートの面を通り過ぎてしまった (くぐり損ね)。放置すると先へ進めなくなる。
	var gate: Node3D = gates[_index]
	if (local - gate.position).dot(gate.normal) > 5.0:
		_ai.reward += reward_miss
		_advance_gate()

	# 距離シェーピング (近づいた分だけ加点 / 遠ざかれば減点)
	var dist := local.distance_to(gates[_index].position)
	if _prev_dist >= 0.0:
		_ai.reward += clampf(_prev_dist - dist, -2.0, 2.0) * reward_approach_scale
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
	_rebuild_course()
	score_changed.emit(score)


## 機体を止めたまま時間も進めない状態にする (カウントダウン / 結果表示中)。
func hold() -> void:
	running = false
	player.freeze = true
	_ai.reset()


## 残り時間の割合 [0, 1]
func time_left_ratio() -> float:
	if _ai.reset_after <= 0:
		return 1.0
	return clampf(1.0 - float(_ai.n_steps) / float(_ai.reset_after), 0.0, 1.0)


## 残り秒数 (物理 60tick = 1 ゲーム秒)
func time_left_seconds() -> float:
	return maxf(float(_ai.reset_after - _ai.n_steps) / 60.0, 0.0)


## 次にくぐるゲート (offset 0) / その次 (offset 1) ... を返す
func gate_at(offset: int) -> Node3D:
	return gates[(_index + offset) % GATE_COUNT]


## 経路上をどれだけ進んだか [m]。VS モードで相手との差を出すのに使う。
## 通過数だけだと「次のゲートまであと少し」の差が見えないので距離で持つ。
func progress_meters() -> float:
	var remaining := to_local(player.global_position).distance_to(gates[_index].position)
	return _travelled + clampf(_leg - remaining, 0.0, _leg)


## 2 本のコースを同じ座標に重ねても互いのリングに反応しないよう、当たり判定を分ける。
## 機体は何とも衝突しない (地面もリングも座標と Area3D で判定しているため)。
func _apply_physics_layer() -> void:
	var bit := 1 << (physics_layer - 1)
	player.collision_layer = bit
	player.collision_mask = 0
	for gate in gates:
		gate.collision_layer = 0
		gate.collision_mask = bit


## Course ローカルの方向ベクトルをワールドへ (学習時はコースを格子状に並べるため)
func global_direction(local_dir: Vector3) -> Vector3:
	return global_transform.basis * local_dir


func _is_out(local: Vector3) -> bool:
	if local.y < CRASH_Y or local.y > CEILING_Y:
		return true
	return Vector2(local.x, local.z).length() > out_of_bounds_radius


## コースを作り直し、機体をスタート地点に戻す。
## 墜落時とエピソード開始時の両方から呼ぶ。
func _rebuild_course() -> void:
	# 同じシードなら必ず同じ形になる。VS モードの 2 本はこれで一致する。
	# 0 のときはランダム。学習中に全コースが同じ形になるのを避けるため。
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_path_pos = Vector3(0.0, START_Y, 0.0)
	_path_dir = Vector3.FORWARD
	_index = 0
	_travelled = 0.0
	for gate in gates:
		_place_gate(gate)
	_highlight_next()

	var spawn := Vector3(0.0, START_Y, 0.0)
	# コースは回転させずに並べるので、ローカル -Z 向き = ワールドの yaw 0
	player.teleport(to_global(spawn), 0.0)
	# teleport 直後は player.global_position がまだ更新されていないことがあるため、
	# スポーン地点から直接計算する (ここを間違えると次フレームに巨大な擬似報酬が出る)
	_prev_dist = spawn.distance_to(gates[_index].position)
	_leg = maxf(_prev_dist, 1.0)


## 墜落してもコース形状を保ち、目標ゲートの手前へ機首を向けて復帰する。
## VS モードで使う。コースを作り直すと相手のゴーストと経路が食い違うため。
func _respawn_at_gate() -> void:
	var gate: Node3D = gates[_index]
	var back: float = minf(_leg * 0.8, GAP_MIN)
	var spawn: Vector3 = gate.position - gate.normal * back
	spawn.y = clampf(spawn.y, GATE_Y_MIN, GATE_Y_MAX)
	# ワールド Y 軸まわりの機首方位。ゲートの法線をそのまま向く。
	var flat := Vector2(gate.normal.x, gate.normal.z)
	var yaw: float = 0.0 if flat.length_squared() < 0.0001 else atan2(-flat.x, -flat.y)
	player.teleport(to_global(spawn), yaw)
	_prev_dist = spawn.distance_to(gate.position)
	_leg = maxf(_prev_dist, 1.0)


func _build_gates() -> void:
	var holder := $Gates
	for i in GATE_COUNT:
		var gate := GATE_SCENE.instantiate()
		holder.add_child(gate)
		gate.passed.connect(_on_gate_passed)
		gate.visible = show_scenery
		gates.append(gate)


## くぐった / 見逃したゲートをコースの先端へ置き直し、目標を次へ送る
func _advance_gate() -> void:
	_travelled += _leg
	var from: Vector3 = gates[_index].position
	_place_gate(gates[_index])
	_index = (_index + 1) % GATE_COUNT
	_highlight_next()
	_leg = maxf(from.distance_to(gates[_index].position), 1.0)
	_prev_dist = to_local(player.global_position).distance_to(gates[_index].position)


func _on_gate_passed(gate: Node3D) -> void:
	if not running or gate != gates[_index]:
		return
	# 逆走してくぐったものは数えない
	if player.linear_velocity.dot(global_direction(gate.normal)) <= 0.0:
		return
	score += 1
	_ai.reward += reward_pass
	gate_passed.emit(gate.global_position)
	_advance_gate()
	score_changed.emit(score)


## コースの先端から次の 1 区間を伸ばし、そこへ gate を移す
func _place_gate(gate: Node3D) -> void:
	var dir := _path_dir.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-MAX_TURN_DEG, MAX_TURN_DEG)))
	var right := dir.cross(Vector3.UP)
	if right.length_squared() > 0.001:
		dir = dir.rotated(right.normalized(), deg_to_rad(_rng.randf_range(-MAX_CLIMB_DEG, MAX_CLIMB_DEG)))
	dir = _steer_inward(_path_pos, dir)

	var pos := _path_pos + dir * _rng.randf_range(GAP_MIN, GAP_MAX)
	pos.y = clampf(pos.y, GATE_Y_MIN, GATE_Y_MAX)
	# 高度をクランプした分だけ向きがずれるので、実際の区間方向から法線を取り直す
	dir = (pos - _path_pos).normalized()

	gate.setup(pos, dir)
	_path_pos = pos
	_path_dir = dir


## 外周や上下限に近づいたら進行方向を中央へ寄せ、コースが発散しないようにする
func _steer_inward(from: Vector3, dir: Vector3) -> Vector3:
	var flat := Vector3(from.x, 0.0, from.z)
	var ratio := flat.length() / course_radius
	if ratio > 0.55 and flat.length_squared() > 0.001:
		var blend := clampf((ratio - 0.55) / 0.45, 0.0, 1.0) * 0.85
		dir = dir.lerp(-flat.normalized(), blend)
	var middle := (GATE_Y_MIN + GATE_Y_MAX) * 0.5
	dir.y = clampf(dir.y + (middle - from.y) / (GATE_Y_MAX - GATE_Y_MIN) * 0.6, -0.55, 0.55)
	return dir.normalized()


func _highlight_next() -> void:
	for i in GATE_COUNT:
		gates[i].set_next(i == _index)


## 高度と速度感が分かるようにグリッドを引く (学習時は不要)
func _build_ground_grid() -> void:
	if DisplayServer.get_name() == "headless" or not show_scenery:
		return
	var half := 90.0
	var step := 10.0
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.34, 0.42, 0.58)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var t := -half
	while t <= half:
		mesh.surface_add_vertex(Vector3(t, 0.0, -half))
		mesh.surface_add_vertex(Vector3(t, 0.0, half))
		mesh.surface_add_vertex(Vector3(-half, 0.0, t))
		mesh.surface_add_vertex(Vector3(half, 0.0, t))
		t += step
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.y = 0.05
	add_child(node)
