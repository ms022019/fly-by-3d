extends Node
## 起動時にどちらのシーンへ進むかを決めるだけの入口。
##
## エクスポートテンプレート (1.2GB) を導入していないため実行ファイルを作れず、
## Python 側から godot バイナリを直接起動する運用になる。
## そのため「どのシーンを開くか」をコマンドライン引数で切り替えている。

const PLAY_SCENE := "res://scenes/play.tscn"
const TRAIN_SCENE := "res://scenes/train.tscn"


func _ready() -> void:
	# _ready 中の即時切り替えはシーンツリーの子操作と衝突するため 1 フレーム遅らせる
	_switch_scene.call_deferred()


func _switch_scene() -> void:
	get_tree().change_scene_to_file(TRAIN_SCENE if _wants_training() else PLAY_SCENE)


func _wants_training() -> bool:
	for argument in OS.get_cmdline_args():
		# --train は自前の指定。--port= は godot-rl が渡してくる引数。
		if argument == "--train" or argument.begins_with("--port="):
			return true
	return false
