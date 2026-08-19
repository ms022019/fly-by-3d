extends Node3D
## Fly By を人間がプレイするシーン。VS モードとソロを 1 つのシーンで扱う。
##
## VS モードでは、同じ形のコースをもう 1 本、同じ座標に重ねて置き、
## そこを学習済み方策 (Policy.drone) の機体が飛ぶ。乱数シードを揃えてあるので
## 2 本はまったく同じ形になり、相手は自分と同じ経路を飛ぶゴーストとして見える。
## 当たり判定は physics_layer で分離してあるので、互いのリングには反応しない。
## AI は Python も TCP も使わず、ゲーム内で推論して動いている。

enum Phase { TITLE, COUNTDOWN, PLAYING, RESULT }

## AI の強さ。方策 (ニューラルネット) は一切いじらず、速度上限と行動ノイズだけを絞る。
## 旋回の角速度は触らない。ドローンは遅いほど小回りが利くので、
## Ball Collector と同じ「全部を skill 倍」では単純な弱体化にならないため。
## 括弧内は 1 機だけで走らせたときの実測スコア
## (godot --headless --path game --bench --bench-speed-cap=N --bench-noise=M で測れる)。
const LEVELS := [
	{"name": "EASY", "speed_cap": 6.0, "noise": 0.35},  # 15.4 gates / 60s
	{"name": "NORMAL", "speed_cap": 9.0, "noise": 0.20},  # 22.5
	{"name": "HARD", "speed_cap": 12.0, "noise": 0.10},  # 28.9
	{"name": "FULL POWER", "speed_cap": 0.0, "noise": 0.0},  # 39.3 (学習したままの全力)
]
const DEFAULT_LEVEL := 1
const COUNTDOWN_SECONDS := 3.0
const HURRY_SECONDS := 10.0

const YOU_COLOR := Color(1.0, 0.55, 0.22)
const AI_COLOR := Color(0.42, 0.72, 1.0)

@onready var course: Node3D = $Course
@onready var rival_course: Node3D = $RivalCourse

var _camera: Camera3D
var _fx: Fx
var _sfx: Sfx

var _phase: int = Phase.TITLE
var _level := DEFAULT_LEVEL
var _versus := true
var _timer := 0.0
var _shake := 0.0
var _best := 0
var _wins := 0
var _losses := 0
var _last_beep := -1

var _hud: Control
var _you_score: Label
var _ai_score: Label
var _ai_name: Label
var _time_label: Label
var _speed_label: Label
var _gap_label: Label
var _center: Label
var _sub_center: Label
var _hint: Label
var _time_bar: ColorRect
var _dim: ColorRect
## スマートフォン用。タッチ画面のときだけ作られる
var _touch: TouchUi = null
var _touch_buttons: Array = []
var _touch_was_active := false
## この時刻まではタップでの開始を受け付けない (msec)。
## 操縦していた指を離した拍子に次のレースが始まってしまうため、
## 結果表示の直後だけ入力を止める。
var _no_tap_until := 0


func _ready() -> void:
	_camera = WorldView.build_world(self)
	_sfx = Sfx.new()
	add_child(_sfx)
	_fx = Fx.new()
	add_child(_fx)
	_fx.track_drone(course.player, YOU_COLOR)
	_fx.track_drone(rival_course.player, AI_COLOR)
	_tint(course.player, YOU_COLOR)
	_tint(rival_course.player, AI_COLOR)

	rival_course.player.policy = Policy.drone()

	_build_hud()
	course.score_changed.connect(_on_score_changed)
	course.gate_passed.connect(_on_gate_passed)
	course.episode_finished.connect(_on_episode_finished)
	rival_course.score_changed.connect(_on_rival_score_changed)

	_build_touch_ui()
	_apply_level()
	_enter_title()
	WorldView.follow_chase(_camera, course.player, 0.0, true)


func _process(delta: float) -> void:
	match _phase:
		Phase.COUNTDOWN:
			_hold()
			_timer -= delta
			_tick_countdown()
		Phase.PLAYING:
			_tick_playing()
		_:
			_hold()

	# タッチが後から検知された場合に、案内文とボタンを出し直す
	if _touch.active != _touch_was_active:
		_touch_was_active = _touch.active
		_refresh_overlay()
	if _touch.active:
		# 画面基準 (下が正) を機体基準 (上げが正) に直す
		course.player.touch_active = true
		course.player.touch = Vector3(
			-_touch.stick.y, _touch.stick.x, -1.0 if _touch.brake else 1.0
		)
	_shake = maxf(_shake - delta * 1.6, 0.0)
	WorldView.follow_chase(_camera, course.player, delta, false, _shake)


func _unhandled_input(event: InputEvent) -> void:
	# スマートフォン: 画面をタップして開始する (SPACE が押せないため)。
	# ただし画面下部はボタンの帯なので除外する。ここを見ないと
	# 「AI の強さ」を押したつもりが同時にレースも始まってしまう。
	if event is InputEventScreenTouch and event.pressed and _phase != Phase.PLAYING:
		if Time.get_ticks_msec() < _no_tap_until:
			return
		if event.position.y < get_viewport().get_visible_rect().size.y - 200.0:
			_enter_countdown()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE, KEY_ENTER:
			if _phase != Phase.PLAYING:
				_enter_countdown()
		KEY_R:
			_enter_countdown()
		KEY_M:
			_versus = not _versus
			_apply_mode()
			if _phase == Phase.PLAYING:
				_enter_countdown()
			else:
				_refresh_overlay()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_level = event.physical_keycode - KEY_1
			_apply_level()
			if _phase == Phase.PLAYING:
				_enter_countdown()
			else:
				_refresh_overlay()
		KEY_G:
			get_tree().change_scene_to_file("res://scenes/play.tscn")
		KEY_ESCAPE:
			get_tree().quit()


#region 進行


func _enter_title() -> void:
	_phase = Phase.TITLE
	_apply_mode()
	_hold()
	_refresh_overlay()


func _enter_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_timer = COUNTDOWN_SECONDS
	_last_beep = -1
	_apply_mode()
	_start_race()
	_hold()
	_refresh_overlay()


## 2 本のコースに同じシードを与えてから作り直す。これで形が一致する。
## 毎回シードを引き直すので、レースごとにコースは変わる。
func _start_race() -> void:
	# 0 は「毎回ランダム」の意味なので避ける
	var seed_value := randi() % 1000000 + 1
	for c in _courses():
		c.rng_seed = seed_value
		# VS ではコースを作り直すと相手と経路が食い違うため、ゲート手前へ復帰させる
		c.respawn_at_gate = _versus
		c.reset_episode()


func _tick_countdown() -> void:
	var remaining := int(ceil(_timer))
	if remaining != _last_beep:
		_last_beep = remaining
		_sfx.play("beep" if remaining > 0 else "go")
	if _timer <= 0.0:
		_phase = Phase.PLAYING
		_start_race()
		_center.text = ""
		_sub_center.text = ""
		_refresh_touch_buttons()
		_hint.text = (
			"drag left : steer      right : brake"
			if _touch.active
			else "W/S : climb, dive    A/D : turn    Shift : brake    R : restart    Esc : quit"
		)
		return
	_center.text = "%d" % remaining if remaining > 0 else "GO!"


func _tick_playing() -> void:
	var left: float = course.time_left_seconds()
	_time_label.text = "%0.1f" % left
	_time_bar.size.x = _time_bar.get_parent().size.x * course.time_left_ratio()
	_speed_label.text = "SPD  %0.1f" % course.player.speed
	_update_gap()

	# 残り 10 秒を切ったら赤く点滅させて秒を刻む
	if left <= HURRY_SECONDS:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.35 + 0.3 * pulse, 0.3))
		var whole := int(ceil(left))
		if whole != _last_beep:
			_last_beep = whole
			_sfx.play("beep", 1.3)
	else:
		_time_label.add_theme_color_override("font_color", WorldView.UI_FONT_COLOR)


## 相手との差を 1 行で出す。同じ経路を飛ぶので、差は「経路上の進行距離」の 1 次元で表せる。
## 秒数は、その距離差を今の自分の速度で割った推定値。
func _update_gap() -> void:
	if not _versus:
		_gap_label.text = ""
		return
	var meters: float = course.progress_meters() - rival_course.progress_meters()
	var gates: int = course.score - rival_course.score
	var seconds: float = absf(meters) / maxf(course.player.speed, 1.0)
	var ahead := meters >= 0.0
	_gap_label.text = "%+d gates   %0.1fs %s" % [gates, seconds, "AHEAD" if ahead else "BEHIND"]
	_gap_label.add_theme_color_override("font_color", YOU_COLOR if ahead else AI_COLOR)


func _on_episode_finished(score: int) -> void:
	_phase = Phase.RESULT
	_no_tap_until = Time.get_ticks_msec() + 1200
	_best = maxi(_best, score)
	if _versus:
		if score > rival_course.score:
			_wins += 1
			_sfx.play("win")
		elif score < rival_course.score:
			_losses += 1
			_sfx.play("lose")
	_shake = 0.35
	_time_label.add_theme_color_override("font_color", WorldView.UI_FONT_COLOR)
	_refresh_overlay()


#endregion


func _courses() -> Array:
	return [course, rival_course] if _versus else [course]


## 進行を止める (タイトル / カウントダウン / 結果表示中)。
## 機体を凍らせたうえで経過 tick も戻すので、残り時間が減らない。
func _hold() -> void:
	for c in [course, rival_course]:
		c.hold()


func _apply_mode() -> void:
	rival_course.visible = _versus
	rival_course.process_mode = (
		Node.PROCESS_MODE_INHERIT if _versus else Node.PROCESS_MODE_DISABLED
	)
	if _ai_name != null:
		_ai_name.visible = _versus
		_ai_score.visible = _versus


func _apply_level() -> void:
	var level: Dictionary = LEVELS[_level]
	rival_course.player.speed_cap = level["speed_cap"]
	rival_course.player.action_noise = level["noise"]
	if _ai_name != null:
		_ai_name.text = "AI  (%s)" % level["name"]


func _refresh_overlay() -> void:
	_dim.visible = _phase == Phase.TITLE or _phase == Phase.RESULT
	_refresh_touch_buttons()
	var mode_text: String = "VS AI" if _versus else "SOLO"
	match _phase:
		Phase.TITLE:
			_center.text = "FLY BY 3D"
			_sub_center.text = (
				(
					"%s\n\n"
					+ "fly through the rings.  the AI is a PPO policy\n"
					+ "trained on this game, now running inside the game itself\n\n"
					+ "AI level:  %s\n\n"
					+ ("tap to start" if _touch.active else "press  SPACE  to start")
				)
				% [mode_text, LEVELS[_level]["name"]]
			)
			_hint.text = (
				"drag the left side to steer      touch the right side to brake"
				if _touch.active
				else (
					"W/S : climb, dive    A/D : turn    Shift : brake"
					+ "    M : mode    G : other game    Esc : quit"
				)
			)
		Phase.COUNTDOWN:
			_sub_center.text = ""
		Phase.RESULT:
			var you: int = course.score
			var ai: int = rival_course.score
			if _versus:
				var verdict := "DRAW"
				if you > ai:
					verdict = "YOU WIN!"
				elif you < ai:
					verdict = "AI WINS"
				_center.text = verdict
				_sub_center.text = (
					(
						"\n\n\nYOU  %d      AI  %d\n\nbest %d      record  %d W - %d L\n\n"
						+ "press  SPACE  to fly again      1-4 : AI level      M : SOLO"
					)
					% [you, ai, _best, _wins, _losses]
				)
			else:
				_center.text = "TIME UP!"
				_sub_center.text = (
					"\n\n\nGATES  %d\n\nbest %d\n\npress  SPACE  to fly again      M : VS AI"
					% [you, _best]
				)
			_hint.text = "SPACE : fly again    1-4 : AI level    M : mode    G : other game"


#region 演出


func _on_score_changed(score: int) -> void:
	_you_score.text = "%d" % score
	if _phase == Phase.PLAYING and score > 0:
		# くぐるほど音を上げていくと、乗っているのが分かる
		_sfx.play("pickup", 1.0 + minf(score, 12) * 0.03)
		_shake = 0.22


func _on_gate_passed(at: Vector3) -> void:
	if _phase == Phase.PLAYING:
		_fx.burst(at, YOU_COLOR, "+1", 0.4)


func _on_rival_score_changed(score: int) -> void:
	_ai_score.text = "%d" % score
	if _phase == Phase.PLAYING and _versus and score > 0:
		_sfx.play("rival")


func _tint(drone: RigidBody3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	for part in ["Fuselage", "Nose", "Wing", "Tail", "Fin"]:
		(drone.get_node(part) as MeshInstance3D).material_override = mat


#endregion


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.07, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_dim)

	# 左: 自分  /  右: AI
	var you_name := WorldView.make_label(_hud, 22, "YOU")
	you_name.position = Vector2(30.0, 14.0)
	you_name.add_theme_color_override("font_color", YOU_COLOR)
	_you_score = WorldView.make_label(_hud, 56, "0")
	_you_score.position = Vector2(30.0, 36.0)
	_speed_label = WorldView.make_label(_hud, 20, "SPD  13.0")
	_speed_label.position = Vector2(30.0, 104.0)

	_ai_name = _make_right_label(22, "AI", 14.0)
	_ai_name.add_theme_color_override("font_color", AI_COLOR)
	_ai_score = _make_right_label(56, "0", 36.0)

	# 中央: 残り時間とライバルとの差
	_time_label = WorldView.make_label(_hud, 46, "60.0")
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.offset_top = 10.0

	var time_track := _make_bar_track(-160.0, 72.0, Vector2(320.0, 5.0))
	_time_bar = _make_bar(time_track, Color(0.85, 0.9, 1.0, 0.85), 320.0)

	_gap_label = WorldView.make_label(_hud, 24, "")
	_gap_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gap_label.offset_top = 86.0

	_center = WorldView.make_label(_hud, 64, "")
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.offset_top = -120.0

	_sub_center = WorldView.make_label(_hud, 22, "")
	_sub_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sub_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_center.offset_top = 60.0

	_hint = WorldView.make_label(_hud, 18, "")
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -42.0


## タッチ画面のときだけ、画面上の操作 UI を作る。
## キーボードが無い端末では SPACE も 1-4 も M も押せないため、
## 開始・AI の強さ・モード切り替えを画面上に置く。
func _build_touch_ui() -> void:
	_touch = TouchUi.new()
	# 判定が false を返すブラウザがあるので、UI 自体は必ず作っておく。
	# その場合でも実際にタッチが来た時点で TouchUi 側が active になる。
	# --force-touch はデスクトップで確認するための開発用。
	_touch.active = (
		DisplayServer.is_touchscreen_available()
		or "--force-touch" in OS.get_cmdline_args()
	)
	_hud.add_child(_touch)

	_touch_buttons = [
		_make_touch_button(-320.0, func(): _cycle_level()),
		_make_touch_button(-100.0, func(): _toggle_mode()),
		_make_touch_button(120.0, func(): get_tree().change_scene_to_file("res://scenes/play.tscn")),
	]
	_refresh_touch_buttons()


func _make_touch_button(offset_x: float, action: Callable) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 22)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset_x
	b.offset_right = offset_x + 200.0
	b.offset_top = -156.0
	b.offset_bottom = -88.0
	b.pressed.connect(action)
	_hud.add_child(b)
	return b


func _cycle_level() -> void:
	_level = (_level + 1) % LEVELS.size()
	_apply_level()
	_refresh_overlay()


func _toggle_mode() -> void:
	_versus = not _versus
	_apply_mode()
	_refresh_overlay()


## ボタンの文字はモードとレベルに追従させ、プレイ中は隠す (指の邪魔になるため)
func _refresh_touch_buttons() -> void:
	if _touch_buttons.is_empty():
		return
	var playing := _phase == Phase.PLAYING or not _touch.active
	_touch_buttons[0].text = "AI: %s" % LEVELS[_level]["name"]
	_touch_buttons[0].visible = not playing and _versus
	_touch_buttons[1].text = "VS AI" if _versus else "SOLO"
	_touch_buttons[1].visible = not playing
	_touch_buttons[2].text = "BALL GAME"
	_touch_buttons[2].visible = not playing


func _make_right_label(font_size: int, text: String, top: float) -> Label:
	var label := WorldView.make_label(_hud, font_size, text)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.offset_left = -260.0
	label.offset_right = -30.0
	label.offset_top = top
	return label


func _make_bar_track(offset_x: float, top: float, size: Vector2) -> Control:
	var track := ColorRect.new()
	track.color = Color(1.0, 1.0, 1.0, 0.12)
	track.set_anchors_preset(Control.PRESET_TOP_LEFT)
	track.anchor_left = 0.5
	track.anchor_right = 0.5
	track.offset_left = offset_x
	track.offset_top = top
	track.size = size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(track)
	return track


func _make_bar(track: Control, color: Color, width: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
	bar.size = Vector2(width, track.size.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	return bar
