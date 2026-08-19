extends Node3D
## 強化学習用シーン。アリーナを格子状に複数並べ、1 プロセス内で同時に学習させる。
## (godot-rl 公式サンプルと同じ構成。1 回の TCP 往復で N 体分の経験が得られる)
##
## ヘッドレスで起動されれば学習用、ウィンドウ付きで起動されれば AI の観戦用になる。

## 並べるシーン (Ball Collector なら arena.tscn、Fly By なら course.tscn)。
## どちらも score / time_left_seconds() / player / auto_reset という同じ口を持つ。
@export var arena_scene: PackedScene = preload("res://scenes/arena.tscn")
@export var arena_count := 16
@export var spacing := 42.0
## true にすると機体を後方から追うカメラになる (Fly By 用)
@export var chase_camera := false

var arenas: Array = []

var _camera: Camera3D
var _status_label: Label


func _ready() -> void:
	var count := _resolve_arena_count()
	var columns := int(ceil(sqrt(float(count))))
	for i in count:
		var arena := arena_scene.instantiate()
		arena.auto_reset = true
		arena.position = Vector3(float(i % columns) * spacing, 0.0, float(i / columns) * spacing)
		add_child(arena)
		arenas.append(arena)

	# ウィンドウがある = 人間が AI のプレイを観ている状況
	if DisplayServer.get_name() != "headless":
		_camera = WorldView.build_world(self)
		_follow(arenas[0].player, 0.0, true)
		_build_hud()


func _process(delta: float) -> void:
	if _camera == null:
		return
	var arena = arenas[0]
	_follow(arena.player, delta)
	_status_label.text = (
		"AI PLAYING      SCORE  %d      TIME  %0.1f" % [arena.score, arena.time_left_seconds()]
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()



func _follow(target: Node3D, delta: float, snap := false) -> void:
	if chase_camera:
		WorldView.follow_chase(_camera, target, delta, snap)
	else:
		WorldView.follow(_camera, target.global_position, delta, snap)


## アリーナ数はコマンドライン (--n_arenas=N) で上書きできる。
## 学習時は多く、観戦時は 1 にする、といった使い分けのため。
func _resolve_arena_count() -> int:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--n_arenas="):
			return maxi(argument.split("=")[1].to_int(), 1)
	return arena_count


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_status_label = WorldView.make_label(layer, 26, "AI PLAYING")
	_status_label.position = Vector2(26.0, 16.0)
	var hint := WorldView.make_label(layer, 18, "Esc : quit")
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_top = -44.0
