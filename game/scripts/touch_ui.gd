extends Control
class_name TouchUi
## スマートフォン用の操作 UI。
##
## 有効になる条件は「実際にタッチ (かポインタ操作) が来たとき」。
## DisplayServer.is_touchscreen_available() での判定はブラウザによって
## false を返すことがあり、その場合スティックが一切作られず操作不能になる。
## 判定に頼らず、来たイベントで判断する。
##
## スティックは「触れた場所に出る」方式。固定位置だと端末の大きさや
## 持ち方で指が届かないため。
##
## マルチタッチを扱うので Button ではなく生のイベントを見ている
## (Fly By では旋回しながらブレーキを踏む同時操作が要るため)。
##
## 出力は画面基準のまま (x = 右が正、y = 下が正) で渡す。
## ゲームごとの意味づけ (機首上げなのか、奥へ転がすのか) は使う側で行う。

## スティックの可動半径 (px)。
## キーボードは押した瞬間に入力が全開になるので、ここを大きく取ると
## タッチだけが不利になる。指を軽く動かせば全開に届く値にしてある。
const RADIUS := 72.0
## この距離までは入力なし扱い。指の微妙なブレを拾わないため
const DEAD_ZONE := 8.0
## 傾きの応答カーブ。1.0 より小さいほど、少し傾けただけでよく効く
const RESPONSE := 0.65

## スティックの傾き。x = 右が正、y = 下が正、長さは 0〜1
var stick := Vector2.ZERO
## ブレーキを押しているか
var brake := false
## 一度でもタッチ操作が来たか。これが false の間は何も描かない
var active := false

## ブレーキ用の領域を使うか。false なら画面全体がスティックになる
## (Ball Collector は 2 軸だけなのでブレーキが要らない)
var use_brake := true

var _stick_index := -1
var _brake_index := -1
var _origin := Vector2.ZERO
var _point := Vector2.ZERO
## タッチイベントが届く環境か。届くならマウスの代替処理は使わない
var _saw_touch := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_saw_touch = true
		_pointer(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_saw_touch = true
		_move(event.index, event.position)
	elif not _saw_touch:
		# タッチイベントが届かない環境でも操作できるようにする保険。
		# ブラウザによっては画面に触れてもマウスイベントしか来ない。
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_pointer(0, event.position, event.pressed)
		elif event is InputEventMouseMotion and _stick_index == 0:
			_move(0, event.position)


func _pointer(index: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		active = true
		var in_stick_area: bool = not use_brake or position.x < size.x * 0.5
		if in_stick_area and _stick_index < 0:
			_stick_index = index
			_origin = position
			_point = position
		elif use_brake and _brake_index < 0:
			_brake_index = index
	else:
		if index == _stick_index:
			_stick_index = -1
		if index == _brake_index:
			_brake_index = -1
	_update()


func _move(index: int, position: Vector2) -> void:
	if index != _stick_index:
		return
	_point = position
	_update()


func _update() -> void:
	var offset := Vector2.ZERO
	if _stick_index >= 0:
		offset = (_point - _origin).limit_length(RADIUS)
		if offset.length() < DEAD_ZONE:
			offset = Vector2.ZERO
	var amount := offset.length() / RADIUS
	stick = Vector2.ZERO if amount <= 0.0 else offset.normalized() * pow(amount, RESPONSE)
	brake = _brake_index >= 0
	queue_redraw()


func _draw() -> void:
	if not active:
		return

	if _stick_index >= 0:
		draw_arc(_origin, RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.16), 3.0, true)
		# つまみは指の位置に追従させる。応答カーブを見た目に反映すると
		# 指とつまみがズレて気持ち悪くなるため
		var knob := (_point - _origin).limit_length(RADIUS)
		draw_circle(_origin + knob, 34.0, Color(1.0, 0.62, 0.25, 0.55))
	else:
		var hint := Vector2(RADIUS + 60.0, size.y - RADIUS - 60.0)
		draw_arc(hint, RADIUS * 0.8, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.10), 2.0, true)

	if use_brake:
		var at := Vector2(size.x - 110.0, size.y - 110.0)
		var fill := Color(0.4, 0.7, 1.0, 0.42) if brake else Color(1.0, 1.0, 1.0, 0.10)
		draw_circle(at, 68.0, fill)
		draw_arc(at, 68.0, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.28), 2.0, true)
