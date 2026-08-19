extends Node
class_name Sfx
## 効果音。波形を起動時に計算して作るので、音声ファイルは 1 つも持たない。
##
## このコンテナにはオーディオデバイスが無く音は鳴らない (Godot はダミードライバに
## 落ちるだけで、エラーにはならない)。Windows ネイティブビルドとブラウザでは鳴る。

const MIX_RATE := 22050
const VOICES := 6

var _players: Array = []
var _next := 0
var _bank := {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	# 人間が取ったときは高く澄んだ音、AI が取ったときは低く鈍い音にして、
	# 画面を見ていなくても「取られた」と分かるようにする。
	_bank["pickup"] = _tone(880.0, 1320.0, 0.13, 0.28, 0.35)
	_bank["rival"] = _tone(300.0, 220.0, 0.16, 0.18, 0.55)
	_bank["fall"] = _tone(420.0, 90.0, 0.42, 0.22, 0.7)
	_bank["beep"] = _tone(660.0, 660.0, 0.10, 0.25, 0.3)
	_bank["go"] = _tone(660.0, 1320.0, 0.30, 0.28, 0.3)
	_bank["win"] = _tone(523.0, 1046.0, 0.55, 0.3, 0.25)
	_bank["lose"] = _tone(392.0, 196.0, 0.55, 0.3, 0.45)


func play(name: String, pitch := 1.0) -> void:
	if not _bank.has(name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _bank[name]
	p.pitch_scale = pitch
	p.play()


## 周波数が from -> to へ滑らかに動く、減衰する音を 1 つ作る。
## square で矩形波成分を混ぜると、正弦波だけより「ゲームらしい」音になる。
func _tone(from: float, to: float, seconds: float, volume: float, square: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var freq: float = lerpf(from, to, t)
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = lerpf(sin(phase), signf(sin(phase)), square)
		# 立ち上がりを一瞬なまして、プチッというノイズを防ぐ
		var envelope: float = minf(t * 40.0, 1.0) * pow(1.0 - t, 2.2)
		var sample := int(clampf(wave * envelope * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
