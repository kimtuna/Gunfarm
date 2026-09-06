extends SceneTree

## 캐릭터 슬롯 저장소(scripts/slot_store.gd) 단독 검증 — 화면이 필요 없다.
##
## 실행:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script qa/qa_slot_store.gd
##
## 슬롯 화면 없이 저장 형식만 확인하므로, 저장 형식을 넓히는 항목(#4 외형, #5 월드 시드)이
## 회귀를 잡는 데 그대로 쓸 수 있다.
##
## 깨진 파일 / 모르는 버전 테스트는 **일부러** 파일을 망가뜨리므로 로그에 JSON 파싱
## ERROR 와 WARNING 이 찍힌다 — 정상이다. 마지막 줄의 PASS/FAIL 과 종료 코드로 판단할 것.

const SlotStore := preload("res://scripts/slot_store.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	_reset()
	_test_starts_empty()
	_test_round_trip()
	_test_broken_file()
	_test_unknown_version()
	_reset()

	if _fails.is_empty():
		print("[qa] PASS — 슬롯 저장소 정상")
		quit(0)
	else:
		for f in _fails:
			printerr("[qa] FAIL — %s" % f)
		quit(1)


func _reset() -> void:
	DirAccess.remove_absolute(SlotStore.SAVE_PATH)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_fails.append(message)


## 저장 파일이 아예 없으면 빈 슬롯 3개다.
func _test_starts_empty() -> void:
	var slots := SlotStore.load_slots()
	_expect(slots.size() == SlotStore.SLOT_COUNT, "슬롯 개수가 %d" % slots.size())
	for i in slots.size():
		_expect(SlotStore.is_empty(slots[i]), "저장 파일이 없는데 슬롯 %d 이 안 비어있다" % (i + 1))


## 저장한 캐릭터가 그대로 다시 읽혀야 한다.
func _test_round_trip() -> void:
	var slots := SlotStore.empty_slots()
	slots[2] = SlotStore.make_character("테스트")
	_expect(SlotStore.save_slots(slots), "저장 실패")

	var loaded := SlotStore.load_slots()
	_expect(SlotStore.is_empty(loaded[0]), "슬롯 1 이 비어있어야 한다")
	_expect(loaded[2].get("name", "") == "테스트", "슬롯 3 이름이 '%s'" % loaded[2].get("name", ""))
	_expect(int(loaded[2].get("created_unix", 0)) > 0, "만든 시각이 안 저장됐다")
	# #4(외형) / #5(월드 시드)가 채울 자리도 형식에 남아있어야 한다.
	_expect(loaded[2].has("appearance"), "appearance 자리가 없다")
	_expect(loaded[2].has("world_seed"), "world_seed 자리가 없다")

	# 삭제 = 그 자리를 빈 슬롯으로 덮어쓰고 저장하는 것.
	loaded[2] = {}
	SlotStore.save_slots(loaded)
	_expect(SlotStore.is_empty(SlotStore.load_slots()[2]), "지운 슬롯이 다시 읽힌다")


## 파일이 깨져도 죽지 말고 빈 슬롯으로 시작해야 한다.
func _test_broken_file() -> void:
	var file := FileAccess.open(SlotStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string("이건 JSON 이 아니다{{{")
	file.close()
	for slot in SlotStore.load_slots():
		_expect(SlotStore.is_empty(slot), "깨진 파일인데 슬롯이 채워졌다")


## 모르는 저장 형식도 마찬가지다 (형식이 바뀌어도 옛 세이브 때문에 못 켜지면 안 된다).
func _test_unknown_version() -> void:
	var file := FileAccess.open(SlotStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 999, "slots": [{"name": "미래"}, {}, {}]}))
	file.close()
	for slot in SlotStore.load_slots():
		_expect(SlotStore.is_empty(slot), "모르는 형식인데 슬롯이 채워졌다")
