extends Node
## 画面をそのまま PNG に保存して終了する、開発用のノード。
## README の図を更新したり、GUI を持たない環境で見た目を確認するために使う。
##
##   xvfb-run -s "-screen 0 1152x648x24" \
##       godot --path game --screenshot=/tmp/shot.png --screenshot-play=12
##
## --screenshot-play=N を付けると、タイトルで SPACE を押してから N 秒後に撮る。

var _path := "user://shot.png"
var _play_seconds := 0.0
var _elapsed := 0.0
var _started := false


func _ready() -> void:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--screenshot="):
			_path = argument.split("=", true, 1)[1]
		elif argument.begins_with("--screenshot-play="):
			_play_seconds = argument.split("=", true, 1)[1].to_float()


func _process(delta: float) -> void:
	_elapsed += delta
	# 最初の数フレームはシーンの構築中なので待つ
	if _elapsed < 0.5:
		return
	if _play_seconds > 0.0 and not _started:
		_started = true
		if "--screenshot-full-power" in OS.get_cmdline_args():
			_press(KEY_4)
		_press(KEY_SPACE)
		return
	if _elapsed < 0.5 + _play_seconds:
		# ゲーム中らしい絵にするため、4 方向を順番に押して転がしておく
		var keys := [KEY_D, KEY_S, KEY_A, KEY_W]
		var active: int = int(_elapsed / 1.2) % keys.size()
		for i in keys.size():
			_press(keys[i], i == active)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_path)
	print("screenshot saved: %s" % _path)
	get_tree().quit()


func _press(key: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
