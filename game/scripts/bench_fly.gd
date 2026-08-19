extends Node3D
## ゲーム内に埋め込んだ方策 (Policy.drone) の実力をヘッドレスで測る。
##
## 2 つの用途がある:
##   1. Python の PPO と同じスコアが出るか (= 移植が正しいか) の確認
##   2. VS モードの手加減 (速度上限とノイズ) を何にすると何点になるかの実測
##
##   godot --headless --path game --bench --bench-speed-cap=9 --bench-noise=0.2
##
## Ball Collector のベンチは早送りできなかった。Engine.time_scale だけを上げると
## 「1 tick が進める時間」が伸びて物理そのものが変わるため (実測: 20 倍で 62 点 -> 2 点)。
## こちらは physics_ticks_per_second も一緒に上げるので、1 tick = 1/60 秒が保たれ、
## 挙動を変えずに実時間だけを縮められる (godot-rl の sync.gd と同じ手法)。

const COURSE_SCENE := preload("res://scenes/course.tscn")

var _episodes := 8
var _courses := 4
var _speed_cap := 0.0
var _noise := 0.0
var _scores: Array = []


func _ready() -> void:
	_episodes = _arg("--bench-episodes=", _episodes)
	_courses = _arg("--bench-courses=", _courses)
	_speed_cap = _arg_float("--bench-speed-cap=", _speed_cap)
	_noise = _arg_float("--bench-noise=", _noise)

	var speed := _arg_float("--bench-speed=", 4.0)
	Engine.physics_ticks_per_second = int(speed * 60.0)
	Engine.time_scale = speed

	for i in _courses:
		var course := COURSE_SCENE.instantiate()
		course.auto_reset = true
		course.show_scenery = false
		course.rng_seed = 1000 + i
		course.position = Vector3(float(i) * 200.0, 0.0, 0.0)
		add_child(course)
		course.player.policy = Policy.drone()
		course.player.speed_cap = _speed_cap
		course.player.action_noise = _noise
		course.episode_finished.connect(_on_episode_finished)

	print(
		(
			"bench: speed_cap %.1f  noise %.2f  courses %d  episodes %d  (x%.0f speed)"
			% [_speed_cap, _noise, _courses, _episodes, speed]
		)
	)


func _on_episode_finished(score: int) -> void:
	if _scores.size() >= _episodes:
		return
	_scores.append(score)
	print("  episode %2d: %3d gates" % [_scores.size(), score])
	if _scores.size() >= _episodes:
		var total := 0
		for s in _scores:
			total += s
		print(
			(
				"bench result: speed_cap %.1f  noise %.2f  mean %.2f  over %d episodes"
				% [_speed_cap, _noise, float(total) / float(_scores.size()), _scores.size()]
			)
		)
		get_tree().quit()


func _arg(prefix: String, fallback: int) -> int:
	for argument in OS.get_cmdline_args():
		if argument.begins_with(prefix):
			return argument.split("=")[1].to_int()
	return fallback


func _arg_float(prefix: String, fallback: float) -> float:
	for argument in OS.get_cmdline_args():
		if argument.begins_with(prefix):
			return argument.split("=")[1].to_float()
	return fallback
