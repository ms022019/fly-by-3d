extends Node3D
class_name Fx
## 見た目の演出をまとめたノード。ルールや物理には一切触れない。
##
## 影は llvmpipe (CPU 描画) には重すぎるので無効にしてある。その代わりに
## 「偽の落下影」を球の真下に置いて、高さと位置が読めるようにしている。
## 演出はすべて非ヘッドレス時のみ生成されるので、学習の速度には影響しない。

const TRAIL_SEGMENTS := 14
const TRAIL_INTERVAL := 0.06
const TRAIL_MIN_SPEED := 1.2
const BURST_POOL := 6
const BURST_SHARDS := 10
const FLOOR_Y := 0.0

var _radial: ImageTexture
var _balls: Array = []
var _bursts: Array = []
var _burst_next := 0
var _pops: Array = []


func _ready() -> void:
	_radial = WorldView.make_radial_texture(64, 1.6)
	for i in BURST_POOL:
		_bursts.append(_Burst.new(self))


## 球に落下影とトレイルを付ける。
func track_ball(ball: RigidBody3D, color: Color) -> void:
	_balls.append(_BallFx.new(self, ball, color, false))


## 機体に落下影とトレイルを付ける (Fly By 用)。
## 球は地面を転がるが機体は高度 8〜28m を飛ぶので、影の見せ方を変える。
## ここでの影は装飾ではなく高度計で、追従カメラでは影が唯一の「今どれくらい高いか」
## の手がかりになる。だから遠ざかっても消さず、代わりに大きく薄くしてぼかす。
func track_drone(drone: RigidBody3D, color: Color) -> void:
	_balls.append(_BallFx.new(self, drone, color, true))


## ターゲットに光の暈 (にじみ) を付ける。glow を使わずに光って見せるための安い代用。
func track_target(target: Node3D, color: Color) -> void:
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 3.4)
	halo.mesh = quad
	halo.material_override = _flat_material(color, BaseMaterial3D.BLEND_MODE_ADD, true)
	halo.position.y = 0.1
	target.get_node("Pivot").add_child(halo)


## 取得の演出。光の輪 + 破片 + "+1" の吹き出し。
## size は見た目の倍率。Ball Collector は俯瞰カメラなので 1.0、
## Fly By は機体のすぐ後ろから見ているので小さくしないと画面を埋め尽くす。
func burst(at: Vector3, color: Color, label := "+1", size := 1.0) -> void:
	_bursts[_burst_next].play(at, color, size)
	_burst_next = (_burst_next + 1) % BURST_POOL
	_pops.append(_Pop.new(self, at, color, label, size))


func _process(delta: float) -> void:
	for b in _balls:
		b.update(delta)
	for b in _bursts:
		b.update(delta)
	var alive: Array = []
	for p in _pops:
		if p.update(delta):
			alive.append(p)
	_pops = alive


func _flat_material(color: Color, blend: int, billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.albedo_color = color
	mat.albedo_texture = _radial
	mat.disable_receive_shadows = true
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat


static func _quad(parent: Node3D, mat: Material, size: float, flat: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	node.mesh = quad
	node.material_override = mat
	if flat:
		node.rotation_degrees.x = -90.0
	parent.add_child(node)
	return node


## 球 1 つぶんの演出 (落下影 + トレイル)
class _BallFx:
	var _ball: RigidBody3D
	var _shadow: MeshInstance3D
	var _segments: Array = []
	var _ages: PackedFloat32Array
	var _next := 0
	var _timer := 0.0
	var _color: Color
	## true = 空を飛ぶ機体。影の高度対応とトレイルの細さが変わる。
	var _air := false

	func _init(root: Fx, ball: RigidBody3D, color: Color, air := false) -> void:
		_ball = ball
		_color = color
		_air = air

		# 球は地面に落ちる影でよいが、空を飛ぶ機体では暗い地面に暗い影が埋もれてしまう。
		# そこで機体色の加算マーカーにして、地面のどこを指しているかを読めるようにする。
		# 加算描画は明るい地面の上では白飛びして見えなくなるので、
		# 明るいテーマのときは通常合成の濃い色に切り替える
		var bright := WorldView.light_theme()
		var shadow_mat: StandardMaterial3D
		if air:
			shadow_mat = (
				root._flat_material(color.darkened(0.25), BaseMaterial3D.BLEND_MODE_MIX, false)
				if bright
				else root._flat_material(color, BaseMaterial3D.BLEND_MODE_ADD, false)
			)
		else:
			shadow_mat = root._flat_material(
				Color(0.0, 0.0, 0.02, 0.6), BaseMaterial3D.BLEND_MODE_MIX, false
			)
		_shadow = Fx._quad(root, shadow_mat, 3.4 if air else 2.6, true)

		var trail_mat := root._flat_material(
			color.darkened(0.15) if bright else color,
			BaseMaterial3D.BLEND_MODE_MIX if bright else BaseMaterial3D.BLEND_MODE_ADD,
			true
		)
		_ages = PackedFloat32Array()
		_ages.resize(Fx.TRAIL_SEGMENTS)
		for i in Fx.TRAIL_SEGMENTS:
			var seg := Fx._quad(root, trail_mat.duplicate(), 1.1 if air else 2.0, false)
			seg.visible = false
			_segments.append(seg)
			_ages[i] = 1.0

	func update(delta: float) -> void:
		var pos := _ball.global_position

		var height := maxf(pos.y - 1.0, 0.0)
		var shadow_mat: StandardMaterial3D = _shadow.material_override
		if _air:
			# 高いほど大きく薄く (ぼけた影に見せる)。ただし完全には消さない。
			# これが唯一の高度の手がかりなので、見失わせない方を優先する。
			var t := clampf(height / 30.0, 0.0, 1.0)
			# 真下ではなく進行方向の先に置く。追従カメラは機体の後方から見ているので、
			# 真下の地面は画面の下端より外に来てしまい、高度計として読めない。
			# 前方に投影すると常に視界に入り、しかも「このまま行くとどこに着くか」も分かる。
			# 機体からマーカーまでの距離がそのまま高度を表す。
			var flat := Vector3(_ball.linear_velocity.x, 0.0, _ball.linear_velocity.z)
			flat = flat.normalized() if flat.length_squared() > 0.01 else Vector3.FORWARD
			var ground := Vector3(pos.x, Fx.FLOOR_Y + 0.12, pos.z) + flat * height * 0.85
			_shadow.global_position = ground
			_shadow.scale = Vector3.ONE * (1.1 + 2.6 * t)
			shadow_mat.albedo_color.a = 0.55 - 0.25 * t
		else:
			# 球: 高いほど薄く小さく
			var fade := clampf(1.0 - height / 7.0, 0.0, 1.0)
			# 真下に置くと球自身の陰に隠れて見えないので、光の向きへ少しずらす
			_shadow.global_position = Vector3(pos.x + 0.9, Fx.FLOOR_Y + 0.04, pos.z + 0.7)
			_shadow.scale = Vector3.ONE * (0.9 + 0.4 * fade)
			shadow_mat.albedo_color.a = 0.6 * fade * (1.0 if pos.y > -2.0 else 0.0)

		# トレイル: 速く動いているときだけ置いていく
		_timer -= delta
		if _timer <= 0.0 and _ball.linear_velocity.length() > Fx.TRAIL_MIN_SPEED:
			_timer = Fx.TRAIL_INTERVAL
			var seg: MeshInstance3D = _segments[_next]
			var back := Vector3.ZERO
			if _air:
				back = -_ball.linear_velocity.normalized() * 1.8
			seg.global_position = pos + back
			seg.visible = true
			_ages[_next] = 0.0
			_next = (_next + 1) % Fx.TRAIL_SEGMENTS

		for i in Fx.TRAIL_SEGMENTS:
			if _ages[i] >= 1.0:
				continue
			_ages[i] = minf(_ages[i] + delta * 2.2, 1.0)
			var seg2: MeshInstance3D = _segments[i]
			var life := 1.0 - _ages[i]
			seg2.scale = Vector3.ONE * (0.35 + 0.65 * life)
			var mat: StandardMaterial3D = seg2.material_override
			mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.75 * life)
			if _ages[i] >= 1.0:
				seg2.visible = false


## 取得時の光の輪と破片。使い回すのでプールに置いておく。
class _Burst:
	var _ring: MeshInstance3D
	var _shards: Array = []
	var _velocities: Array = []
	var _life := -1.0
	var _size := 1.0

	func _init(root: Fx) -> void:
		_ring = Fx._quad(root, root._flat_material(Color.WHITE, BaseMaterial3D.BLEND_MODE_ADD, false), 3.0, true)
		_ring.visible = false
		for i in Fx.BURST_SHARDS:
			var shard := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.22, 0.22)
			shard.mesh = box
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shard.material_override = mat
			shard.visible = false
			root.add_child(shard)
			_shards.append(shard)
			_velocities.append(Vector3.ZERO)

	func play(at: Vector3, color: Color, size := 1.0) -> void:
		_life = 0.0
		_size = size
		_ring.global_position = at + Vector3(0.0, 0.05, 0.0)
		_ring.visible = true
		(_ring.material_override as StandardMaterial3D).albedo_color = color
		for i in _shards.size():
			var angle := TAU * float(i) / float(_shards.size()) + randf() * 0.4
			var speed := randf_range(5.0, 9.0) * size
			_velocities[i] = Vector3(
				cos(angle) * speed, randf_range(4.0, 8.0) * size, sin(angle) * speed
			)
			var shard: MeshInstance3D = _shards[i]
			shard.global_position = at
			shard.visible = true
			(shard.material_override as StandardMaterial3D).albedo_color = color

	func update(delta: float) -> void:
		if _life < 0.0:
			return
		_life += delta
		var t := _life / 0.55
		if t >= 1.0:
			_life = -1.0
			_ring.visible = false
			for shard in _shards:
				shard.visible = false
			return

		# 光の輪: 一気に広がって消える
		_ring.scale = Vector3.ONE * (0.4 + 2.6 * t) * _size
		var ring_mat: StandardMaterial3D = _ring.material_override
		ring_mat.albedo_color.a = 1.0 - t

		for i in _shards.size():
			var shard2: MeshInstance3D = _shards[i]
			_velocities[i] += Vector3(0.0, -22.0 * _size * delta, 0.0)
			shard2.global_position += _velocities[i] * delta
			shard2.rotation += Vector3(6.0, 4.0, 2.0) * delta
			shard2.scale = Vector3.ONE * (1.0 - t) * _size


## "+1" の吹き出し
class _Pop:
	var _label: Label3D

	var _size := 1.0

	func _init(root: Fx, at: Vector3, color: Color, text: String, size := 1.0) -> void:
		_size = size
		_label = Label3D.new()
		_label.text = text
		_label.font_size = 96
		_label.pixel_size = 0.018 * size
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate = color
		_label.outline_size = 10
		_label.outline_modulate = Color(0.0, 0.0, 0.05, 0.55)
		root.add_child(_label)
		_label.global_position = at + Vector3(0.0, 1.2 * size, 0.0)

	## 生きていれば true
	func update(delta: float) -> bool:
		_label.global_position.y += delta * 2.6 * _size
		_label.modulate.a -= delta * 1.5
		if _label.modulate.a <= 0.0:
			_label.queue_free()
			return false
		return true
