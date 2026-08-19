extends Control
class_name TouchUi
## スマートフォン用の操作 UI。タッチ画面のときだけ表示される。
##
## 画面の左半分がスティック、右半分がブレーキ。
## スティックは「触れた場所に出る」方式にしてある。固定位置だと端末の大きさや
## 持ち方で指が届かないため。
##
## マルチタッチを扱うので Button ではなく生のタッチイベントを見ている
## (旋回しながらブレーキを踏む、という同時操作が要るため)。

## スティックの可動半径 (px)
const RADIUS := 120.0
## この距離までは入力なし扱い。指の微妙なブレを拾わないため
const DEAD_ZONE := 14.0

## 操作入力。drone.gd の control と同じ意味 (x = ピッチ, y = ヨー, z = スロットル)
var value := Vector3(0.0, 0.0, 1.0)

var _stick_index := -1
var _brake_index := -1
var _origin := Vector2.ZERO
var _point := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < size.x * 0.5 and _stick_index < 0:
				_stick_index = event.index
				_origin = event.position
				_point = event.position
			elif _brake_index < 0:
				_brake_index = event.index
		else:
			if event.index == _stick_index:
				_stick_index = -1
			if event.index == _brake_index:
				_brake_index = -1
		_update()
	elif event is InputEventScreenDrag and event.index == _stick_index:
		_point = event.position
		_update()


func _update() -> void:
	var offset := Vector2.ZERO
	if _stick_index >= 0:
		offset = (_point - _origin).limit_length(RADIUS)
		if offset.length() < DEAD_ZONE:
			offset = Vector2.ZERO
	# 画面の上方向 = 機首上げなので y は反転する
	value = Vector3(
		clampf(-offset.y / RADIUS, -1.0, 1.0),
		clampf(offset.x / RADIUS, -1.0, 1.0),
		-1.0 if _brake_index >= 0 else 1.0
	)
	queue_redraw()


func _draw() -> void:
	var base := Color(1.0, 1.0, 1.0, 0.16)
	var lit := Color(1.0, 0.62, 0.25, 0.55)

	# スティック (触れているときだけ描く)
	if _stick_index >= 0:
		draw_arc(_origin, RADIUS, 0.0, TAU, 48, base, 3.0, true)
		draw_circle(_origin + (_point - _origin).limit_length(RADIUS), 34.0, lit)
	else:
		# 触れていないときは、左下に置き場所のヒントだけ出す
		var hint := Vector2(RADIUS + 40.0, size.y - RADIUS - 40.0)
		draw_arc(hint, RADIUS * 0.55, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.09), 2.0, true)

	# ブレーキ (右下)
	var brake := Vector2(size.x - 110.0, size.y - 110.0)
	var held := _brake_index >= 0
	draw_circle(brake, 68.0, Color(0.4, 0.7, 1.0, 0.42) if held else Color(1.0, 1.0, 1.0, 0.10))
	draw_arc(brake, 68.0, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.28), 2.0, true)
