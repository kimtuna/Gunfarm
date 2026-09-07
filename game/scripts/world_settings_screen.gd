extends Control

## 월드 설정 화면 (docs/DESIGN.md 「월드 설정」). 지금 있는 항목은 **데스드롭 상자
## 타이머** 하나다.
##
## **「설정」(해상도)과 일부러 다른 화면이다.** 그쪽은 `user://settings.json` 에
## **기계 단위**로 저장되고(이 모니터의 사정이다), 이쪽은 **그 월드(슬롯)에** 저장된다 —
## 같은 사람이 월드를 여러 개 만들면 서로 다를 수 있다. 값을 들고 있는 것은
## `world_settings.gd`(순수 클래스)이고, 슬롯에 적는 것은 띄운 쪽(`world.gd`)이다
## (「서버 권위」: 월드 설정은 그 월드를 여는 호스트의 것이라, 나중에 서버가 들고 판정에 쓴다).
##
## **이 화면은 자기 Esc 를 처리하지 않는다** — 월드 위에 겹쳐 뜬 창이라 닫는 것은
## 띄운 쪽이다(「조작」 Esc 항목의 "가장 안쪽 창부터", `settings.gd` 의 `as_overlay` 와
## 같은 규칙).

const WorldSettings := preload("res://scripts/world_settings.gd")

## 값이 바뀌었다 — 슬롯에 적는 것은 띄운 쪽(`world.gd`)이다.
signal changed

var settings: RefCounted = null


func setup(new_settings: RefCounted) -> void:
	settings = new_settings
	_refresh()


func _ready() -> void:
	(%NextButton as Button).grab_focus()
	if settings != null:
		_refresh()


func _refresh() -> void:
	if settings == null:
		return
	(%DeathBoxValue as Label).text = WorldSettings.minutes_label(settings.death_box_minutes)


func _on_prev_pressed() -> void:
	_step(-1)


func _on_next_pressed() -> void:
	_step(1)


## **이미 놓여 있는 상자의 남은 시간은 안 건드린다** — 상자는 만들어질 때의 값을
## 새겨두고(`death_boxes.gd` 의 `spawn`), 이 설정은 **다음에 생기는 상자**부터
## 적용된다. 근거는 docs/DESIGN.md 「월드 설정」에 적었다.
func _step(delta: int) -> void:
	if settings == null:
		return
	settings.step_death_box(delta)
	_refresh()
	changed.emit()
