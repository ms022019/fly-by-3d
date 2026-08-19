extends RigidBody3D
## ゲートをくぐる機体。
##
## 入力元は 3 通りあり、どれを使っても物理とルールは同じコードを通る:
##   policy != null       -> ゲーム内に埋め込んだ学習済み方策 (VS モードのライバル)
##   heuristic == "human" -> キーボード
##   それ以外             -> Python (godot-rl) から届いた行動
##
## Ball Collector の球 (player.gd) と決定的に違うのは制御の座標系。
## こちらは「機体ローカル」で操作する。ピッチ角とヨー角を状態として持ち、
## 毎フレーム basis を作り直して機首方向 (-Z) へ進む。
## 物理エンジンに任せるのは速度の積分と当たり判定だけ。
##
## ロール (bank) は見た目だけの傾き。YXZ 順のオイラー角ではロールが最内側に入るため、
## 機首方向まわりの回転となり進行方向を変えない。

## 学習時の action_repeat と同じ間隔で行動を決める。
## 学習時は 8 physics tick に 1 回しか行動を選び直していないので、
## ここを 1 にすると「学習したときと違う挙動」になってしまう。
const POLICY_ACTION_REPEAT := 8

## スロットル全開 / 全閉のときの速度 (m/s)
@export var min_speed := 8.0
@export var max_speed := 18.0
## リスポーン直後の速度
@export var start_speed := 13.0
## 速度の変化率 (m/s^2)。これが無いとブレーキが一瞬で効いて駆け引きにならない。
@export var accel := 16.0
## ピッチ / ヨーの最大角速度 (rad/s)
@export var pitch_rate := 1.9
@export var yaw_rate := 1.9
## 背面飛行に入ると人間が混乱するので機首角は制限する
@export var max_pitch_deg := 60.0
## 旋回時の見た目のバンク角 (物理には影響しない)
@export var bank_deg := 38.0

@onready var ai := $AIController

## この機体が属する Course。Course._ready() から代入される。
var course: Node3D
## 操作入力。x = ピッチ (+1 で機首上げ)、y = ヨー (+1 で右旋回)、z = スロットル (+1 で最高速)。
var control := Vector3(0.0, 0.0, 1.0)
## 現在の前進速度 (m/s)
var speed := 13.0
## 埋め込み方策。代入するとこの機体は AI が操作する。
var policy: Policy = null
## 手加減用の速度上限 (0 = 制限なし)。
## observation の正規化に使う max_speed とは意図的に別の変数にしてある。
## max_speed を下げると観測のスケールまで変わり、方策が見る世界が歪むため。
var speed_cap := 0.0
## 手加減用の行動ノイズ (標準偏差)。大きいほど狙いを外す。
var action_noise := 0.0

## タッチ UI からの入力 (スマートフォン用)。play_fly.gd が毎フレーム書き込む。
var touch := Vector3(0.0, 0.0, 1.0)
var touch_active := false

var _policy_action := Vector3(0.0, 0.0, 1.0)
var _policy_wait := 0

var _pitch := 0.0
var _yaw := 0.0
var _bank := 0.0


func _ready() -> void:
	add_to_group("player")
	ai.init(self)


func _physics_process(_delta: float) -> void:
	if policy != null:
		control = _think()
	elif ai.heuristic == "human":
		control = _read_input()
	else:
		control = ai.control


## 埋め込み方策で行動を決める。観測は AIController.get_obs() を通すので、
## 学習時に Python へ送っていたものと 1 ビットも違わない。
func _think() -> Vector3:
	if _policy_wait <= 0:
		var a := policy.act(ai.get_obs()["obs"])
		var out := Vector3(a[0], a[1], a[2])
		if action_noise > 0.0:
			out.x = clampf(out.x + randfn(0.0, action_noise), -1.0, 1.0)
			out.y = clampf(out.y + randfn(0.0, action_noise), -1.0, 1.0)
			out.z = clampf(out.z + randfn(0.0, action_noise), -1.0, 1.0)
		_policy_action = out
		_policy_wait = POLICY_ACTION_REPEAT
	_policy_wait -= 1
	return _policy_action


## 姿勢と速度は物理サーバー側で直接置き換える。
## 「トルクを加えて安定するのを待つ」構成より応答が素直で、
## 人間の操作感と AI の行動空間の意味が完全に一致する。
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.step
	var limit := deg_to_rad(max_pitch_deg)
	_pitch = clampf(_pitch + control.x * pitch_rate * delta, -limit, limit)
	_yaw = wrapf(_yaw - control.y * yaw_rate * delta, -PI, PI)
	_bank = lerpf(_bank, -control.y * deg_to_rad(bank_deg), 1.0 - pow(0.0005, delta))

	# 旋回の角速度は速度によらず一定にしてある。つまり遅く飛ぶほど小回りが利き、
	# 「きつい曲がりの手前で減速する」という駆け引きが生まれる。
	var target_speed := lerpf(min_speed, max_speed, (control.z + 1.0) * 0.5)
	if speed_cap > 0.0:
		target_speed = minf(target_speed, speed_cap)
	speed = move_toward(speed, target_speed, accel * delta)

	var b := Basis.from_euler(Vector3(_pitch, _yaw, _bank), EULER_ORDER_YXZ)
	var t := state.transform
	t.basis = b
	state.transform = t
	state.linear_velocity = -b.z * speed
	state.angular_velocity = Vector3.ZERO


func _read_input() -> Vector3:
	# スロットルは既定で全開。ブレーキだけを押す方式にして操作を単純に保つ。
	var v := Vector3(0.0, 0.0, 1.0)
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		v.z = -1.0
	if touch_active:
		# キーボードとタッチのどちらでも操作できるよう、入力があった方を採る
		if absf(touch.x) > absf(v.x):
			v.x = touch.x
		if absf(touch.y) > absf(v.y):
			v.y = touch.y
		v.z = minf(v.z, touch.z)
	return v


## RigidBody3D を安全に瞬間移動させる (player.gd の teleport と同じ理由で body_set_state を使う)。
## yaw はワールド Y 軸まわりの機首方位 [rad]。
func teleport(target: Vector3, yaw: float) -> void:
	_pitch = 0.0
	_yaw = yaw
	_bank = 0.0
	speed = minf(start_speed, speed_cap) if speed_cap > 0.0 else start_speed
	_policy_wait = 0
	var b := Basis.from_euler(Vector3(0.0, yaw, 0.0), EULER_ORDER_YXZ)
	var t := Transform3D(b, target)
	var rid := get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, -b.z * speed)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
