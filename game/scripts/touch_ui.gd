extends Control
class_name TouchUi
## スマートフォン用の操作 UI。タッチ画面のときだけ表示される。
##
## スティックは「触れた場所に出る」方式にしてある。固定位置だと端末の大きさや
## 持ち方で指が届かないため。
##
## マルチタッチを扱うので Button ではなく生のタッチイベントを見ている
## (Fly By では旋回しながらブレーキを踏む同時操作が要るため)。
##
## 出力は画面基準のまま (x = 右が正、y = 下が正) で渡す。
## ゲームごとの意味づけ (機首上げなのか、奥へ転がすのか) は使う側で行う。

## スティックの可動半径 (px)
const RADIUS := 120.0
## この距離までは入力なし扱い。指の微妙なブレを拾わないため
const DEAD_ZONE := 14.0

## スティックの傾き。x = 右が正、y = 下が正、長さは 0〜1
var stick := Vector2.ZERO
## ブレーキを押しているか
var brake := false

## ブレーキ用の領域を使うか。false なら画面全体がスティックになる
## (Ball Collector は 2 軸だけなのでブレーキが要らない)
var use_brake := true

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
			var in_stick_area: bool = not use_brake or event.position.x < size.x * 0.5
			if in_stick_area and _stick_index < 0:
				_stick_index = event.index
				_origin = event.position
				_point = event.position
			elif use_brake and _brake_index < 0:
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
	stick = offset / RADIUS
	brake = _brake_index >= 0
	queue_redraw()


func _draw() -> void:
	if _stick_index >= 0:
		draw_arc(_origin, RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.16), 3.0, true)
		draw_circle(_origin + stick * RADIUS, 34.0, Color(1.0, 0.62, 0.25, 0.55))
	else:
		# 触れていないときは、置き場所のヒントだけ薄く出す
		var hint := Vector2(RADIUS + 40.0, size.y - RADIUS - 40.0)
		draw_arc(hint, RADIUS * 0.55, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.09), 2.0, true)

	if use_brake:
		var at := Vector2(size.x - 110.0, size.y - 110.0)
		var fill := Color(0.4, 0.7, 1.0, 0.42) if brake else Color(1.0, 1.0, 1.0, 0.10)
		draw_circle(at, 68.0, fill)
		draw_arc(at, 68.0, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.28), 2.0, true)
