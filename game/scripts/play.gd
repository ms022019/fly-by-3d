extends Node3D
## 人間がプレイするシーン。
##
## 同じフィールドに、学習済み方策 (BallPolicy) で動くライバルが 1 体いる。
## ターゲットは共有なので、先に取った方の得点になる取り合いになる。
## AI は Python も TCP も使わず、ゲーム内で推論して動いている。

enum Phase { TITLE, COUNTDOWN, PLAYING, RESULT }

## AI の強さ。方策 (ニューラルネット) は一切いじらず、トルクと速度上限だけを絞る。
## 括弧内は 1 体だけで走らせたときの実測スコア
## (godot --headless --path game --bench --bench-skill=N で測れる)。
const LEVELS := [
	{"name": "EASY", "skill": 0.12},  # 15.3 targets / 60s
	{"name": "NORMAL", "skill": 0.20},  # 24.5
	{"name": "HARD", "skill": 0.35},  # 33.7 (手書きの貪欲方策と同じくらい)
	{"name": "FULL POWER", "skill": 1.00},  # 66.5 (学習したままの全力)
]
const DEFAULT_LEVEL := 1
const COUNTDOWN_SECONDS := 3.0
const HURRY_SECONDS := 10.0
const PAD_SIZE := 92.0

@onready var arena: Arena = $Arena

var _camera: Camera3D
var _fx: Fx
var _sfx: Sfx

var _phase: int = Phase.TITLE
var _level := DEFAULT_LEVEL
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
var _center: Label
var _sub_center: Label
var _hint: Label
var _you_bar: ColorRect
var _ai_bar: ColorRect
var _time_bar: ColorRect
var _dim: ColorRect
var _you_dot: ColorRect
var _ai_dot: ColorRect


func _ready() -> void:
	_camera = WorldView.build_world(self)
	_sfx = Sfx.new()
	add_child(_sfx)
	_fx = Fx.new()
	add_child(_fx)
	_fx.track_ball(arena.player, Arena.PLAYER_COLOR)
	_fx.track_ball(arena.rival, Arena.RIVAL_COLOR)
	for t in arena.targets:
		_fx.track_target(t, Color(1.0, 0.72, 0.2, 0.9))

	_build_hud()
	arena.score_changed.connect(_on_score_changed)
	arena.rival_score_changed.connect(_on_rival_score_changed)
	arena.episode_finished.connect(_on_episode_finished)
	arena.target_collected.connect(_on_target_collected)
	arena.ball_fell.connect(_on_ball_fell)

	_apply_level()
	_enter_title()
	WorldView.follow(_camera, arena.player.global_position, 0.0, true)


func _process(delta: float) -> void:
	match _phase:
		Phase.COUNTDOWN:
			arena.hold()
			_timer -= delta
			_tick_countdown()
		Phase.PLAYING:
			_tick_playing()
		_:
			arena.hold()

	_update_pads()
	_shake = maxf(_shake - delta * 1.6, 0.0)
	var focus: Vector3 = arena.player.global_position
	var spread := 0.0
	if arena.rival != null:
		var to_rival: Vector3 = arena.rival.global_position - focus
		spread = to_rival.length()
		# 自分を中心に置きつつ、ライバルの方へ少しだけ寄せて両方を画面に入れる
		focus += to_rival.limit_length(9.0) * 0.35
	# フィールドはほぼ画面に収まる大きさなので、追従は控えめにして
	# 場外の空白が画面に入り込まないようにする。
	var center: Vector3 = arena.global_position
	var limit: float = arena.arena_size * 0.5 - 10.0
	focus = center + (focus - center) * 0.45
	focus.x = clampf(focus.x, center.x - limit, center.x + limit)
	focus.z = clampf(focus.z, center.z - limit, center.z + limit)
	WorldView.follow(_camera, focus, delta, false, spread, _shake)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE, KEY_ENTER:
			if _phase != Phase.PLAYING:
				_enter_countdown()
		KEY_R:
			_enter_countdown()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_level = event.physical_keycode - KEY_1
			_apply_level()
			if _phase == Phase.PLAYING:
				_enter_countdown()
			else:
				_refresh_overlay()
		KEY_G:
			get_tree().change_scene_to_file("res://scenes/play_fly.tscn")
		KEY_ESCAPE:
			get_tree().quit()


#region 進行


func _enter_title() -> void:
	_phase = Phase.TITLE
	arena.hold()
	_refresh_overlay()


func _enter_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_timer = COUNTDOWN_SECONDS
	_last_beep = -1
	arena.reset_episode()
	arena.hold()
	_refresh_overlay()


func _tick_countdown() -> void:
	var remaining := int(ceil(_timer))
	if remaining != _last_beep:
		_last_beep = remaining
		_sfx.play("beep" if remaining > 0 else "go")
	if _timer <= 0.0:
		_phase = Phase.PLAYING
		arena.reset_episode()
		_center.text = ""
		_sub_center.text = ""
		_hint.text = (
			"WASD / Arrows : roll      1-4 : AI level"
			+ "      R : restart      G : other game      Esc : quit"
		)
		return
	_center.text = "%d" % remaining if remaining > 0 else "GO!"


func _tick_playing() -> void:
	var left := arena.time_left_seconds()
	_time_label.text = "%0.1f" % left
	_time_bar.size.x = _time_bar.get_parent().size.x * arena.time_left_ratio()

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


func _on_episode_finished(score: int) -> void:
	_phase = Phase.RESULT
	_best = maxi(_best, score)
	if score > arena.rival_score:
		_wins += 1
		_sfx.play("win")
	elif score < arena.rival_score:
		_losses += 1
		_sfx.play("lose")
	_shake = 0.35
	_time_label.add_theme_color_override("font_color", WorldView.UI_FONT_COLOR)
	_refresh_overlay()


#endregion


func _apply_level() -> void:
	if arena.rival != null:
		arena.rival.skill = LEVELS[_level]["skill"]
	if _ai_name != null:
		_ai_name.text = "AI  (%s)" % LEVELS[_level]["name"]


func _refresh_overlay() -> void:
	_dim.visible = _phase == Phase.TITLE or _phase == Phase.RESULT
	match _phase:
		Phase.TITLE:
			_center.text = "BALL COLLECTOR 3D"
			_sub_center.text = (
				"YOU  vs  AI\n\n"
				+ "the AI is a PPO policy trained on this game,\n"
				+ "now running inside the game itself\n\n"
				+ "AI level:  %s      (1-4 to change)\n\n"
				+ "press  SPACE  to start"
			) % LEVELS[_level]["name"]
			_hint.text = (
				"WASD / Arrows : roll      1-4 : AI level      G : other game      Esc : quit"
			)
		Phase.COUNTDOWN:
			_sub_center.text = ""
		Phase.RESULT:
			var you: int = arena.score
			var ai: int = arena.rival_score
			var verdict := "DRAW"
			if you > ai:
				verdict = "YOU WIN!"
			elif you < ai:
				verdict = "AI WINS"
			_center.text = verdict
			_sub_center.text = (
				"\n\n\nYOU  %d      AI  %d\n\nbest %d      record  %d W - %d L\n\n"
				+ "press  SPACE  to play again      1-4 : AI level"
			) % [you, ai, _best, _wins, _losses]
			_hint.text = (
				"SPACE : play again      1-4 : AI level      G : other game      Esc : quit"
			)


#region 演出


func _on_target_collected(at: Vector3, by_rival: bool) -> void:
	if by_rival:
		_fx.burst(at, Arena.RIVAL_COLOR)
		_sfx.play("rival")
	else:
		_fx.burst(at, Arena.PLAYER_COLOR)
		# 取るほど音を上げていくと、乗っているのが分かる
		_sfx.play("pickup", 1.0 + minf(arena.score, 12) * 0.03)
		_shake = 0.28


func _on_ball_fell(ball: RigidBody3D) -> void:
	if ball == arena.player:
		_sfx.play("fall")
		_shake = 0.5


func _on_score_changed(score: int) -> void:
	_you_score.text = "%d" % score
	_update_bars()


func _on_rival_score_changed(score: int) -> void:
	_ai_score.text = "%d" % score
	_update_bars()


## 画面下の 2 つのパッドに、人間の入力と AI の出力をそのまま表示する。
## どちらも同じ 2 次元の連続値 (X/Z トルク) で、同じ物理を通っていることが目で分かる。
func _update_pads() -> void:
	_you_dot.position = _dot_position(arena.player.move)
	if arena.rival != null:
		_ai_dot.position = _dot_position(arena.rival.move)


func _dot_position(move: Vector2) -> Vector2:
	var half := PAD_SIZE * 0.5
	return Vector2(half + move.x * (half - 6.0) - 5.0, half + move.y * (half - 6.0) - 5.0)


## 上部のバーで「どちらがどれだけ取っているか」を一目で見せる
func _update_bars() -> void:
	var you: int = arena.score
	var ai: int = arena.rival_score
	var total: float = maxf(float(you + ai), 1.0)
	var width: float = _you_bar.get_parent().size.x
	_you_bar.size.x = width * (float(you) / total)
	_ai_bar.size.x = width * (float(ai) / total)
	_ai_bar.position.x = width - _ai_bar.size.x


#endregion


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	# タイトル / 結果表示のときだけ world を暗くして、文字を読みやすくする
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.07, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_dim)

	# 左: 自分  /  右: AI
	var you_name := WorldView.make_label(_hud, 22, "YOU")
	you_name.position = Vector2(30.0, 14.0)
	you_name.add_theme_color_override("font_color", Arena.PLAYER_COLOR)
	_you_score = WorldView.make_label(_hud, 56, "0")
	_you_score.position = Vector2(30.0, 36.0)

	_ai_name = _make_right_label(22, "AI", 14.0)
	_ai_name.add_theme_color_override("font_color", Arena.RIVAL_COLOR)
	_ai_score = _make_right_label(56, "0", 36.0)

	# 中央: 残り時間
	_time_label = WorldView.make_label(_hud, 46, "60.0")
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.offset_top = 10.0

	var time_track := _make_bar_track(-160.0, 72.0, Vector2(320.0, 5.0))
	_time_bar = _make_bar(time_track, Color(0.85, 0.9, 1.0, 0.85), 320.0)

	# 得点の取り合いを示すバー (左が自分、右が AI)
	var score_track := _make_bar_track(-230.0, 84.0, Vector2(460.0, 12.0))
	_you_bar = _make_bar(score_track, Arena.PLAYER_COLOR, 0.0)
	_ai_bar = _make_bar(score_track, Arena.RIVAL_COLOR, 0.0)

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

	# 人間の入力と AI の出力を並べて見せる
	_you_dot = _make_pad(30.0, "YOUR INPUT", Arena.PLAYER_COLOR)
	_ai_dot = _make_pad(-30.0 - PAD_SIZE, "AI OUTPUT (PPO)", Arena.RIVAL_COLOR)


## 行動 (X/Z の 2 次元) を表示する小さなパッド。返すのは中の点。
## offset_x が正なら左端から、負なら右端からの位置。
func _make_pad(offset_x: float, title: String, color: Color) -> ColorRect:
	var pad := ColorRect.new()
	pad.color = Color(0.0, 0.0, 0.0, 0.35)
	pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if offset_x >= 0.0 else Control.PRESET_BOTTOM_RIGHT)
	pad.anchor_left = 0.0 if offset_x >= 0.0 else 1.0
	pad.anchor_right = pad.anchor_left
	pad.anchor_top = 1.0
	pad.anchor_bottom = 1.0
	pad.offset_left = offset_x
	pad.offset_right = offset_x + PAD_SIZE
	pad.offset_top = -PAD_SIZE - 62.0
	pad.offset_bottom = -62.0
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(pad)

	# 中心の十字 (原点 = 入力なし)
	for horizontal in [true, false]:
		var line := ColorRect.new()
		line.color = Color(1.0, 1.0, 1.0, 0.15)
		line.position = (
			Vector2(0.0, PAD_SIZE * 0.5) if horizontal else Vector2(PAD_SIZE * 0.5, 0.0)
		)
		line.size = Vector2(PAD_SIZE, 1.0) if horizontal else Vector2(1.0, PAD_SIZE)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(line)

	var caption := WorldView.make_label(pad, 13, title)
	caption.position = Vector2(0.0, -20.0)
	caption.add_theme_color_override("font_color", color)

	var dot := ColorRect.new()
	dot.color = color
	dot.size = Vector2(10.0, 10.0)
	dot.position = Vector2(PAD_SIZE * 0.5 - 5.0, PAD_SIZE * 0.5 - 5.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(dot)
	return dot


## 画面右端に寄せたラベル
func _make_right_label(font_size: int, text: String, top: float) -> Label:
	var label := WorldView.make_label(_hud, font_size, text)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left = -330.0
	label.offset_right = -30.0
	label.offset_top = top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


## バーの下地 (画面中央上に置く)
func _make_bar_track(offset_x: float, offset_y: float, size: Vector2) -> Control:
	var track := ColorRect.new()
	track.color = Color(0.0, 0.0, 0.0, 0.22)
	track.anchor_left = 0.5
	track.anchor_right = 0.5
	track.offset_left = offset_x
	track.offset_right = offset_x + size.x
	track.offset_top = offset_y
	track.offset_bottom = offset_y + size.y
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(track)
	return track


func _make_bar(track: Control, color: Color, width: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
	bar.position = Vector2.ZERO
	bar.size = Vector2(width, track.size.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar)
	return bar
