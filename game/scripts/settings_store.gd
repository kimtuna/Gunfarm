extends RefCounted

## 그래픽 설정(해상도)의 저장/불러오기/적용 (docs/DESIGN.md "카메라 / 해상도").
##
## slot_store.gd 와 같은 이유로 노드를 상속하지 않는 순수 클래스다 — 화면 없이
## 단독으로 돌아가야 하고, 오토로드는 `--script` 자체 QA에서 컴파일 에러를 낸다
## (docs/GOTCHAS.md).
##
## **PvP 공정성**: 해상도는 창의 픽셀 크기와 선명도만 바꾼다. 카메라가 보여주는
## 월드 범위는 항상 BASE_SIZE(논리 해상도) 그대로다 — project.godot 의
## stretch mode=canvas_items / aspect=keep 이 그걸 보장한다.

const SAVE_PATH := "user://settings.json"
const FORMAT_VERSION := 1

## 논리 해상도. project.godot 의 window/size/viewport_width/height 와 반드시 같아야 한다.
## 이 값이 곧 "화면에 보이는 월드 범위"다.
## (2026-09-10 사람이 1440x810 에서 넓혔다 — docs/DESIGN.md "카메라 / 해상도".
## 그전 이력: 2026-09-08 에 1280x720 → 1440x810.)
##
## **project.godot 을 고치는 바퀴는 여기도 같이 고친다.** 2026-09-10 에 실제로 어긋났다 —
## project.godot 만 1920x1080 이 되고 이 값이 1440x810 으로 남으니, 창을 논리 해상도에
## 맞춘다고 믿는 검사(`qa_inventory` `qa_hotbar` `qa_death_box`)가 배율 0.75 짜리 창에서
## 돌면서 마우스 좌표와 화면 픽셀이 통째로 어긋났다.
const BASE_SIZE := Vector2i(1920, 1080)

## 고를 수 있는 해상도. 전부 16:9 다 — 논리 해상도와 비율이 같아야 검은 여백 없이
## 꽉 찬다(비율이 다른 창은 여백이 생길 뿐, 보이는 월드 범위는 그대로다).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## 창의 기본 크기. **반드시 RESOLUTIONS 안의 값**이어야 하고(목록에 없는 크기를
## 기본값으로 두면 설정 화면이 고를 수 없는 값을 보여준다), project.godot 의
## window/size/window_*_override 와도 같아야 한다 — 안 그러면 창이 한 크기로 떴다가
## 메인 메뉴에서 다른 크기로 튄다.
##
## **2026-09-10 에 BASE_SIZE 와 다시 같아졌다.** 2026-09-08~10 동안만 달랐는데, 그건
## 논리 해상도 1440x810 이 RESOLUTIONS 에 없는 값이라 어쩔 수 없이 갈랐던 것이다.
## 1920x1080 은 목록에 있으므로 가를 이유가 사라졌고, 같아지면 기본 창의 배율이 1 이 되어
## 도트가 축소로 깎이지 않는다(그전에는 1440x810 을 1280x720 창에 **0.889 배로 줄여**
## 그리고 있었다 — docs/DESIGN.md "카메라 / 해상도").
## **창 크기와 논리 해상도는 여전히 다른 개념이다** — 창은 이 그림을 확대/축소해 보여줄
## 뿐이고, 사람이 설정에서 다른 크기를 고르면 다시 갈린다.
const DEFAULT_SIZE := Vector2i(1920, 1080)


static func default_settings() -> Dictionary:
	return {"resolution": DEFAULT_SIZE}


## 지금 화면(모니터)에 실제로 들어가는 해상도만 고를 수 있게 거른다.
## `current` 는 이미 저장돼 있는 값이라 화면보다 커도 목록에 남긴다(고른 걸 잃지 않게).
static func available_resolutions(current := Vector2i.ZERO) -> Array[Vector2i]:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var list: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if (size.x <= usable.x and size.y <= usable.y) or size == current:
			list.append(size)
	if list.is_empty():
		list.append(DEFAULT_SIZE)  # 어떤 화면에서도 최소 하나는 고를 수 있어야 한다.
	return list


static func load_settings() -> Dictionary:
	var settings := default_settings()
	if not FileAccess.file_exists(SAVE_PATH):
		return settings
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("설정을 못 읽었다: %s" % error_string(FileAccess.get_open_error()))
		return settings
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("설정 파일이 깨졌다 — 기본값으로 시작한다.")
		return settings
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("모르는 설정 형식(version=%s) — 기본값으로 시작한다." % data.get("version", 0))
		return settings
	# JSON 은 숫자를 float 로 준다 → int 로 감싼다 (docs/GOTCHAS.md).
	var size := Vector2i(int(data.get("resolution_width", 0)), int(data.get("resolution_height", 0)))
	if RESOLUTIONS.has(size):
		settings["resolution"] = size
	else:
		push_warning("모르는 해상도 %s — 기본값을 쓴다." % size)
	return settings


static func save_settings(settings: Dictionary) -> bool:
	var size: Vector2i = settings.get("resolution", DEFAULT_SIZE)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("설정을 못 썼다: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({
		"version": FORMAT_VERSION,
		"resolution_width": size.x,
		"resolution_height": size.y,
	}, "\t"))
	file.close()
	return true


## 창 크기만 바꾼다. 논리 해상도(BASE_SIZE)는 건드리지 않으므로 보이는 월드 범위는 그대로다.
static func apply_resolution(size: Vector2i) -> void:
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
	_center_window(size)


## 저장된 해상도를 창에 반영한다. 진입 씬(메인 메뉴)이 시작할 때 한 번 부른다.
static func apply_saved() -> Vector2i:
	var size: Vector2i = load_settings().get("resolution", DEFAULT_SIZE)
	apply_resolution(size)
	return size


static func _center_window(size: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
