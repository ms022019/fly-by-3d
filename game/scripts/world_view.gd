extends Node
class_name WorldView
## 見る側 (カメラ・ライト・空・床・HUD) の組み立てをまとめたヘルパー。
## 人間プレイ (play.gd) と AI 観戦 (train.gd) の両方から使う。

## カメラは球体を追従するが、回転は固定する。
## こうすることで「画面奥 = ワールド -Z = W キー」が常に成立し、
## 人間の操作方向と AI の行動空間の意味が一致する。
## 見下ろし角を強めにして、フィールド全体とターゲットの配置が読めるようにする。
const CAM_OFFSET := Vector3(0.0, 20.0, 17.0)
const CAM_PITCH := -50.0

const UI_FONT_COLOR := Color(0.96, 0.97, 1.0)


static func build_world(root: Node3D) -> Camera3D:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.06, 0.08, 0.22)
	sky_material.sky_horizon_color = Color(0.36, 0.40, 0.66)
	# カメラは見下ろしているので、画面の外側はほぼ「空の地面側」で埋まる。
	# ここを真っ黒にすると寂しいので、紫寄りのグラデーションにしている。
	sky_material.ground_bottom_color = Color(0.07, 0.06, 0.16)
	sky_material.ground_horizon_color = Color(0.26, 0.24, 0.44)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.25
	# 遠くを薄く霞ませると、影が無くても奥行きが出る (影は llvmpipe には重すぎる)
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.28, 0.30, 0.50)
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.0

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	# llvmpipe (CPU 描画) なので影は無効。影を有効にすると一気に重くなる。
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	light.light_energy = 1.25
	light.light_color = Color(1.0, 0.96, 0.9)
	light.shadow_enabled = false
	root.add_child(light)

	# 影の代わりに、下から弱い青い光を当てて球の輪郭を出す
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(35.0, 140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.shadow_enabled = false
	root.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)
	root.add_child(camera)
	camera.current = true
	return camera


## カメラを focus 地点の上に置く。回転は常に固定。
## spread: 2 つの球がどれだけ離れているか。離れるほど少し引いて両方を画面に入れる。
## shake: 取得時などに軽く揺らす量。
static func follow(
	camera: Camera3D, focus: Vector3, delta: float, snap := false, spread := 0.0, shake := 0.0
) -> void:
	var zoom := 1.0 + clampf(spread / 60.0, 0.0, 0.28)
	var goal := focus + CAM_OFFSET * zoom
	if snap:
		camera.global_position = goal
	else:
		camera.global_position = camera.global_position.lerp(goal, 1.0 - pow(0.0015, delta))
	if shake > 0.0:
		camera.global_position += Vector3(
			randf_range(-shake, shake), randf_range(-shake, shake), randf_range(-shake, shake)
		)
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)


## --- Fly By 用: 機体を後方から追うカメラ ---
## Ball Collector と違い、Fly By は機体ローカル座標系で操作するので、
## カメラも機首の向きに合わせて回さないと「入力の向き」と「見えている向き」がズレる。
## 機体ローカルでのカメラ位置 (後方かつ少し上)
const CHASE_OFFSET := Vector3(0.0, 2.6, 9.5)
## 注視点を機首の前方どれだけ先に置くか
const CHASE_LOOK_AHEAD := 14.0
## カメラを機体のバンクにどれだけ付き合わせるか (0 = 水平線を常に水平に保つ)
const CHASE_ROLL_MIX := 0.3


static func follow_chase(
	camera: Camera3D, target: Node3D, delta: float, snap := false, shake := 0.0
) -> void:
	var t := target.global_transform
	var goal := t * CHASE_OFFSET
	if snap:
		camera.global_position = goal
	else:
		camera.global_position = camera.global_position.lerp(goal, 1.0 - pow(1e-9, delta))
	if shake > 0.0:
		camera.global_position += Vector3(
			randf_range(-shake, shake), randf_range(-shake, shake), randf_range(-shake, shake)
		)
	# 上方向はワールド上方向を主にし、機体のバンクを少しだけ混ぜる。
	# 全部機体に合わせると、見た目だけのバンクで水平線が大きく傾いて酔う。
	# ピッチは ±60 度に制限されているので、この up が視線と平行になることはない。
	var up := Vector3.UP.lerp(t.basis.y, CHASE_ROLL_MIX).normalized()
	camera.look_at(t.origin - t.basis.z * CHASE_LOOK_AHEAD, up)


## 床用のグリッド素材。影が無いので、マス目が距離感の唯一の手がかりになる。
## テクスチャは実行時に生成する (画像アセットを持たずに済む)。
static func make_floor_material(arena_size: float) -> StandardMaterial3D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.17, 0.20, 0.29)
	var line := Color(0.36, 0.44, 0.62)
	for y in size:
		for x in size:
			var on_line := x < 2 or y < 2
			image.set_pixel(x, y, line if on_line else base)
	var texture := ImageTexture.create_from_image(image)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.uv1_scale = Vector3(arena_size / 3.0, arena_size / 3.0, arena_size / 3.0)
	mat.metallic = 0.1
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


## 中心が明るく外へ向かって消える円。落下影・光の輪・パーティクルに使い回す。
static func make_radial_texture(size := 64, power := 2.0) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(image)


## Godot 標準フォントは日本語グリフを持たないため、HUD の文字は ASCII に限定する。
static func make_label(parent: Node, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UI_FONT_COLOR)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
