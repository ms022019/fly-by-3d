extends RefCounted
class_name Policy
## 学習済み PPO 方策の推論を GDScript だけで行う。
##
## godot-rl 同梱の ONNX 推論はプラグインの C# 実装に依存していて、この環境の
## Godot (非 .NET ビルド) では動かない。だがこの方策は obs -> 64 -> 64 -> action の
## MLP でしかないので、重みを埋め込んで自前で行列積を回している。
## おかげで Python も TCP 接続も無しに、Web ビルドの中で AI が動く。
##
## PPO の決定論的な行動は「行動分布の平均」そのもの、つまり action_net の出力。
## 学習時 (SB3 の predict) と同じく [-1, 1] にクリップする。
##
## 2 つのゲームで観測・行動の次元が違う (Ball Collector 12->2 / Fly By 17->3) ので、
## 重みは外から渡す。tools/export_policy.py が生成する *_weights.gd がその供給元。

var obs_size: int
var hidden: int
var action_size: int

var _w0: PackedFloat32Array
var _b0: PackedFloat32Array
var _w1: PackedFloat32Array
var _b1: PackedFloat32Array
var _w2: PackedFloat32Array
var _b2: PackedFloat32Array

# 毎フレーム確保し直さないよう作業用バッファを持ち回す
var _h0 := PackedFloat32Array()
var _h1 := PackedFloat32Array()
var _out := PackedFloat32Array()


## sizes = [観測次元, 隠れ層, 行動次元] / b64 = [W0, B0, W1, B1, W2, B2]
func _init(sizes: Array, b64: Array) -> void:
	obs_size = sizes[0]
	hidden = sizes[1]
	action_size = sizes[2]
	_w0 = _decode(b64[0])
	_b0 = _decode(b64[1])
	_w1 = _decode(b64[2])
	_b1 = _decode(b64[3])
	_w2 = _decode(b64[4])
	_b2 = _decode(b64[5])
	_h0.resize(hidden)
	_h1.resize(hidden)
	_out.resize(action_size)


static func ball() -> Policy:
	return Policy.new(
		[PolicyWeights.OBS_SIZE, PolicyWeights.HIDDEN, PolicyWeights.ACTION_SIZE],
		[
			PolicyWeights.W0_B64,
			PolicyWeights.B0_B64,
			PolicyWeights.W1_B64,
			PolicyWeights.B1_B64,
			PolicyWeights.W2_B64,
			PolicyWeights.B2_B64,
		]
	)


static func drone() -> Policy:
	return Policy.new(
		[
			DronePolicyWeights.OBS_SIZE,
			DronePolicyWeights.HIDDEN,
			DronePolicyWeights.ACTION_SIZE,
		],
		[
			DronePolicyWeights.W0_B64,
			DronePolicyWeights.B0_B64,
			DronePolicyWeights.W1_B64,
			DronePolicyWeights.B1_B64,
			DronePolicyWeights.W2_B64,
			DronePolicyWeights.B2_B64,
		]
	)


static func for_game(game: String) -> Policy:
	return drone() if game == "flyby" else ball()


## 観測 (obs_size 次元) から行動を返す。返り値は使い回しのバッファなので、
## 次の呼び出しまでに読み終えること。
func act(obs: Array) -> PackedFloat32Array:
	act_raw(obs)
	for i in action_size:
		_out[i] = clampf(_out[i], -1.0, 1.0)
	return _out


## クリップ前の生の出力。Python 側 (tools/export_policy.py) との照合に使う。
func act_raw(obs: Array) -> PackedFloat32Array:
	_layer_tanh(obs, _w0, _b0, _h0, obs_size, hidden)
	_layer_tanh(_h0, _w1, _b1, _h1, hidden, hidden)
	var base := 0
	for j in action_size:
		var sum := _b2[j]
		for i in hidden:
			sum += _w2[base + i] * _h1[i]
		_out[j] = sum
		base += hidden
	return _out


## out[j] = tanh(sum_i w[j * in_size + i] * x[i] + b[j])
func _layer_tanh(
	x, w: PackedFloat32Array, b: PackedFloat32Array, out: PackedFloat32Array,
	in_size: int, out_size: int
) -> void:
	var base := 0
	for j in out_size:
		var sum := b[j]
		for i in in_size:
			sum += w[base + i] * x[i]
		out[j] = tanh(sum)
		base += in_size


static func _decode(b64: String) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(b64).to_float32_array()
