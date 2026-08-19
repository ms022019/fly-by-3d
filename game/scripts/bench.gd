extends Node3D
## ゲーム内に埋め込んだ方策 (BallPolicy) の実力をヘッドレスで測る。
##
## 2 つの用途がある:
##   1. Python の PPO と同じスコアが出るか (= 移植が正しいか) の確認
##   2. VS モードの手加減 (skill) を何倍にすると何点になるかの実測
##
##   godot --headless --path game --bench --bench-skill=0.6 --bench-episodes=8

const ARENA_SCENE := preload("res://scenes/arena.tscn")

var _episodes := 8
var _arenas := 8
var _skill := 1.0
var _scores: Array = []


func _ready() -> void:
	_episodes = _arg("--bench-episodes=", _episodes)
	_arenas = _arg("--bench-arenas=", _arenas)
	_skill = _arg_float("--bench-skill=", _skill)
	# 早送りは既定で無効。Godot の time_scale は「1 tick が進める時間」を伸ばすので、
	# 上げると物理そのものが変わってしまい (実測: 20 倍で 62 点 -> 2 点)、
	# 実力を測る目的では使えない。
	Engine.time_scale = _arg_float("--bench-speed=", 1.0)

	for i in _arenas:
		var arena := ARENA_SCENE.instantiate()
		arena.auto_reset = true
		arena.player_is_policy = true
		arena.position = Vector3(float(i) * 60.0, 0.0, 0.0)
		add_child(arena)
		arena.player.skill = _skill
		arena.episode_finished.connect(_on_episode_finished)

	print("bench: skill %.2f  arenas %d  episodes %d" % [_skill, _arenas, _episodes])


func _on_episode_finished(score: int) -> void:
	if _scores.size() >= _episodes:
		return
	_scores.append(score)
	print("  episode %2d: %3d targets" % [_scores.size(), score])
	if _scores.size() >= _episodes:
		var total := 0
		for s in _scores:
			total += s
		print("bench result: skill %.2f  mean %.2f  over %d episodes" % [
			_skill, float(total) / float(_scores.size()), _scores.size()
		])
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
