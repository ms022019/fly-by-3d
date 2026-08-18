extends Node3D
## 人間がプレイするシーン。

@onready var arena: Node3D = $Arena

var _camera: Camera3D
var _score_label: Label
var _time_label: Label
var _result_label: Label
var _best_score := 0


func _ready() -> void:
	_camera = WorldView.build_world(self)
	WorldView.follow(_camera, arena.player, 0.0, true)
	_build_hud()
	arena.score_changed.connect(_on_score_changed)
	arena.episode_finished.connect(_on_episode_finished)


func _process(delta: float) -> void:
	WorldView.follow(_camera, arena.player, delta)
	_time_label.text = "%0.1f" % arena.time_left_seconds()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_R:
			_restart()
		KEY_ESCAPE:
			get_tree().quit()


func _restart() -> void:
	_result_label.visible = false
	arena.reset_episode()


func _on_score_changed(score: int) -> void:
	_score_label.text = "SCORE  %d      BEST  %d" % [score, _best_score]


func _on_episode_finished(score: int) -> void:
	_best_score = maxi(_best_score, score)
	_score_label.text = "SCORE  %d      BEST  %d" % [score, _best_score]
	_result_label.text = "TIME UP!\n\nSCORE  %d\n\npress  R  to play again" % score
	_result_label.visible = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_score_label = WorldView.make_label(layer, 26, "SCORE  0      BEST  0")
	_score_label.position = Vector2(26.0, 16.0)

	_time_label = WorldView.make_label(layer, 44, "60.0")
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.offset_top = 12.0

	var hint := WorldView.make_label(
		layer, 18, "WASD / Arrow keys : roll      R : restart      Esc : quit"
	)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_top = -44.0

	_result_label = WorldView.make_label(layer, 40, "")
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.visible = false
