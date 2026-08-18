extends Node
class_name WorldView
## 見る側 (カメラ・ライト・空・HUD) の組み立てをまとめたヘルパー。
## 人間プレイ (play.gd) と AI 観戦 (train.gd) の両方から使う。

## カメラは球体を追従するが、回転は固定する。
## こうすることで「画面奥 = ワールド -Z = W キー」が常に成立し、
## 人間の操作方向と AI の行動空間の意味が一致する。
## 見下ろし角を強めにして、フィールド全体とターゲットの配置が読めるようにする。
const CAM_OFFSET := Vector3(0.0, 24.0, 20.0)
const CAM_PITCH := -50.0


static func build_world(root: Node3D) -> Camera3D:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.09, 0.12, 0.25)
	sky_material.sky_horizon_color = Color(0.38, 0.45, 0.62)
	sky_material.ground_bottom_color = Color(0.05, 0.06, 0.11)
	sky_material.ground_horizon_color = Color(0.20, 0.24, 0.36)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.35

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	# llvmpipe (CPU 描画) なので影は無効。影を有効にすると一気に重くなる。
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	light.light_energy = 1.3
	light.shadow_enabled = false
	root.add_child(light)

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)
	root.add_child(camera)
	camera.current = true
	return camera


static func follow(camera: Camera3D, target: Node3D, delta: float, snap := false) -> void:
	var goal := target.global_position + CAM_OFFSET
	if snap:
		camera.global_position = goal
	else:
		camera.global_position = camera.global_position.lerp(goal, 1.0 - pow(0.0015, delta))
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)


## Godot 標準フォントは日本語グリフを持たないため、HUD の文字は ASCII に限定する。
static func make_label(parent: Node, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
