extends Resource
class_name ONNXModel

## NOTE: この環境の Godot は非 .NET (標準) ビルドのため、
## 本家プラグインの C# 実装による ONNX 推論は利用できません。
## 学習済みモデルで遊ばせる場合は Python 側 (tools/play_ai.py) から env を駆動してください。

var action_output_size: int
var action_means_only: bool
var action_means_only_set: bool


func _init(model_path, batch_size):
	push_error(
		(
			"ONNX inference is unavailable: this project runs on a non-.NET Godot build. "
			+ "Use tools/play_ai.py (Python-side inference) instead. Requested model: %s (batch %d)"
			% [model_path, batch_size]
		)
	)


func run_inference(_obs: Dictionary, _state_ins: int) -> Dictionary:
	push_error("ONNX inference is unavailable on a non-.NET Godot build.")
	return {}


func set_action_means_only(_action_space: Dictionary) -> void:
	action_means_only_set = true
