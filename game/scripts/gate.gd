extends Area3D
## くぐるリング。Course から setup() で位置と向きを与えられる。
##
## 当たり判定はリングの「穴」だけを覆う薄い円柱にしてある。
## フレーム部分に当たり判定は無く、外側をかすめても通過にはならない。

signal passed(gate: Node3D)

const COLOR_NEXT := Color(1.0, 0.78, 0.22)
const COLOR_LATER := Color(0.35, 0.62, 0.95)

## くぐるべき向き (Course ローカル座標系)。逆走判定に使う。
var normal := Vector3.FORWARD

var _material: StandardMaterial3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# 学習時 (ヘッドレス) は見た目の処理を一切しない
	if DisplayServer.get_name() == "headless":
		return
	_material = StandardMaterial3D.new()
	_material.metallic = 0.2
	_material.roughness = 0.35
	_material.emission_enabled = true
	$Mesh.material_override = _material
	set_next(false)


## 位置と進行方向を与える。ローカル -Z が normal を向くように姿勢を組む
## (Mesh と Collision は tscn 側で「ローカル Z 軸 = リングの軸」に回してある)。
func setup(local_pos: Vector3, dir: Vector3) -> void:
	normal = dir.normalized()
	var z_axis := -normal
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var x_axis := up.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis)
	transform = Transform3D(Basis(x_axis, y_axis, z_axis), local_pos)


## 次にくぐるべきゲートだけ色を変える (人間が目標を見失わないように)
func set_next(is_next: bool) -> void:
	if _material == null:
		return
	var color := COLOR_NEXT if is_next else COLOR_LATER
	_material.albedo_color = color
	_material.emission = color
	_material.emission_energy_multiplier = 2.2 if is_next else 1.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		passed.emit(self)
