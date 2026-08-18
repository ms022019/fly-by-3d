extends Area3D
## 集めるターゲット。取得されると collected を emit し、Arena が別位置へ再配置する。

signal collected(target: Node3D)

@export var spin_speed := 1.8

@onready var _pivot: Node3D = $Pivot

var _t := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU
	# 学習時 (ヘッドレス) は見た目の演出を止めて負荷を下げる。
	# 演出は Pivot(見た目) のみを動かし、Area3D 本体は動かさないので
	# 当たり判定は人間プレイ時と学習時で完全に一致する。
	if DisplayServer.get_name() == "headless":
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y += spin_speed * delta
	_pivot.position.y = sin(_t * 2.0) * 0.22


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collected.emit(self)
