extends RigidBody3D
## トルクで転がる球体プレイヤー。
## 人間操作 (heuristic == "human") と AI 操作 (AIController から受け取る) の両方を扱う。

@export var torque_strength := 14.0
## 速度上限。観測値のスケールを安定させる意味もある。
@export var max_speed := 14.0

@onready var ai := $AIController

## このプレイヤーが所属する Arena。Arena._ready() から代入される。
var arena: Node3D
## 現在の移動入力。x = ワールド +X 方向、y = ワールド +Z 方向。
var move := Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	ai.init(self)


func _physics_process(_delta: float) -> void:
	if ai.heuristic == "human":
		move = _read_input()
	else:
		move = ai.move

	# 球を転がすトルク: +X へ進むには -Z 軸まわり、+Z へ進むには +X 軸まわりに回す
	apply_torque(Vector3(move.y, 0.0, -move.x) * torque_strength)

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed


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
