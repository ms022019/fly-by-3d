extends RigidBody3D
## トルクで転がる球体プレイヤー。
##
## 入力元は 3 通りあり、どれを使っても物理とルールは同じコードを通る:
##   policy != null      -> ゲーム内に埋め込んだ学習済み方策 (VS モードのライバル)
##   heuristic == "human" -> キーボード
##   それ以外            -> Python (godot-rl) から届いた行動

## 学習時の action_repeat と同じ間隔で行動を決める。
## 学習時は 8 physics tick に 1 回しか行動を選び直していないので、
## ここを 1 にすると「学習したときと違う挙動」になってしまう。
const POLICY_ACTION_REPEAT := 8

@export var torque_strength := 14.0
## 速度上限。観測値のスケールを安定させる意味もある。
@export var max_speed := 14.0

@onready var ai := $AIController

## このプレイヤーが所属する Arena。Arena._ready() から代入される。
var arena: Node3D
## 現在の移動入力。x = ワールド +X 方向、y = ワールド +Z 方向。
var move := Vector2.ZERO
## 埋め込み方策。代入するとこの球は AI が操作する。
var policy: Policy = null
## ライバルの手加減。トルクと速度上限に掛かる (1.0 = 学習したときの全力)。
var skill := 1.0

var _policy_action := Vector2.ZERO
var _policy_wait := 0


func _ready() -> void:
	add_to_group("player")
	ai.init(self)


func _physics_process(_delta: float) -> void:
	if policy != null:
		move = _think()
	elif ai.heuristic == "human":
		move = _read_input()
	else:
		move = ai.move

	# 球を転がすトルク: +X へ進むには -Z 軸まわり、+Z へ進むには +X 軸まわりに回す
	apply_torque(Vector3(move.y, 0.0, -move.x) * torque_strength * skill)

	var limit := max_speed * skill
	if linear_velocity.length() > limit:
		linear_velocity = linear_velocity.normalized() * limit


## 埋め込み方策で行動を決める。観測は AIController.get_obs() を通すので、
## 学習時に Python へ送っていたものと 1 ビットも違わない。
func _think() -> Vector2:
	if _policy_wait <= 0:
		var a := policy.act(ai.get_obs()["obs"])
		_policy_action = Vector2(a[0], a[1])
		_policy_wait = POLICY_ACTION_REPEAT
	_policy_wait -= 1
	return _policy_action


func _read_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	return v.limit_length(1.0)


## RigidBody3D を安全に瞬間移動させる。
## global_position への直接代入は物理サーバーに無視されうるため body_set_state を使う。
func teleport(target: Vector3) -> void:
	var t := global_transform
	t.origin = target
	var rid := get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_policy_wait = 0
