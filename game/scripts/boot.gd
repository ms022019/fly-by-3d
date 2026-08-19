extends Node
## 起動時にどのシーンへ進むかを決めるだけの入口。
##
## エクスポートテンプレートを前提にしない運用 (Python 側から godot バイナリを
## 直接起動する) のため、「どのシーンを開くか」をコマンドライン引数で切り替えている。
##
##   --train             学習 / AI 観戦シーンを開く (godot-rl が渡す --port= でも同じ)
##   --game=flyby|ball   どちらのゲームを開くか (既定は flyby)
##   --bench             ゲーム内 AI の実力をヘッドレスで測る
##   --policy-probe      埋め込み方策の移植チェック (Python 側の参照値と突き合わせる)
##   --screenshot=...    シーン切り替えで消えない位置に撮影ノードを置く

const GAMES := {
	"flyby":
	{
		"play": "res://scenes/play_fly.tscn",
		"train": "res://scenes/train_fly.tscn",
		"bench": "res://scenes/bench_fly.tscn",
	},
	"ball":
	{
		"play": "res://scenes/play.tscn",
		"train": "res://scenes/train.tscn",
		"bench": "res://scenes/bench.tscn",
	},
}
const DEFAULT_GAME := "flyby"


func _ready() -> void:
	if "--policy-probe" in OS.get_cmdline_args():
		_policy_probe()
		get_tree().quit()
		return
	_install_screenshot()
	# _ready 中の即時切り替えはシーンツリーの子操作と衝突するため 1 フレーム遅らせる
	_switch_scene.call_deferred()


## --screenshot=... が指定されていれば、シーン切り替えで消えない位置に撮影ノードを置く。
func _install_screenshot() -> void:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--screenshot="):
			var node := preload("res://scripts/screenshot.gd").new()
			get_tree().root.add_child.call_deferred(node)
			return


## Python 側 (tools/export_policy.py) と同じ入力を入れて、クリップ前の出力を表示する。
## 埋め込んだ重みが正しく復元できているかの確認に使う。
func _policy_probe() -> void:
	for game in GAMES:
		var policy := Policy.for_game(game)
		var obs: Array = []
		for i in policy.obs_size:
			obs.append(sin(float(i)) * 0.3)
		var raw := policy.act_raw(obs)
		var text := ""
		for value in raw:
			text += " %+.6f" % value
		print("probe %s action(raw):%s" % [game, text])


func _switch_scene() -> void:
	var game: Dictionary = GAMES[_wants_game()]
	if "--bench" in OS.get_cmdline_args():
		get_tree().change_scene_to_file(game["bench"])
		return
	get_tree().change_scene_to_file(game["train"] if _wants_training() else game["play"])


func _wants_game() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--game="):
			var name := argument.split("=")[1]
			if GAMES.has(name):
				return name
			push_warning("unknown --game=%s, falling back to %s" % [name, DEFAULT_GAME])
	return DEFAULT_GAME


func _wants_training() -> bool:
	for argument in OS.get_cmdline_args():
		# --train は自前の指定。--port= は godot-rl が渡してくる引数。
		if argument == "--train" or argument.begins_with("--port="):
			return true
	return false
