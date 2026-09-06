extends SceneTree

# 자체 QA — Godot 이 만드는 **임포트 메타파일**의 관리 규칙 검증.
# 두 종류를 같은 규칙으로 본다:
#   * 스크립트마다 생기는 `*.gd.uid`        (2026-09-06 결정, INBOX #6)
#   * 임포트되는 자산마다 생기는 `*.import` (2026-09-06 결정, INBOX #7 — png/svg/ogg 등)
#
# 규칙 (근거는 CLAUDE.md 「git」 참고): 둘 다 **커밋한다**.
#   1) 모든 원본 파일 옆에 짝이 되는 메타파일이 있다.
#   2) 원본이 지워졌는데 남은 고아 메타파일이 없다.
#   3) 모든 메타파일이 git 에 추적되고 있다 (매 바퀴 untracked 로 쌓이지 않는다).
#
# 새 스크립트나 새 그림을 만든 바퀴는 `--import` 를 한 번 돌린 뒤 이걸로 확인한다.
#
# 실행:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
#     --script qa/qa_uid_files.gd > /tmp/qa_uid.log 2>&1; echo $?

# `.import` 메타파일이 생기는 자산 확장자. Godot 이 임포트하는 종류는 더 많지만,
# 여기 없는 확장자는 "짝이 있는가"(규칙 1)를 검사하지 않을 뿐 고아/미추적 검사(2·3)는
# 그대로 걸린다 — 새 종류의 자산을 처음 넣는 바퀴가 이 목록에 추가한다.
const IMPORTED_EXTS: Array[String] = ["png", "svg", "jpg", "jpeg", "webp", "ogg", "wav", "mp3"]

var _fails: Array[String] = []

func _initialize() -> void:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var files := _collect(game_dir)
	var tracked := _git_tracked(game_dir)
	if tracked.is_empty():
		_fail("git ls-files 가 아무것도 못 찾았다 — git 실행 자체가 실패했을 수 있다")

	var scripts := _filter_suffix(files, ".gd")
	var uids := _filter_suffix(files, ".gd.uid")
	var assets := _filter_imported_assets(files)
	var imports := _filter_suffix(files, ".import")
	print("스크립트 %d개 / uid %d개, 자산 %d개 / import %d개 (기준 디렉터리: %s)"
		% [scripts.size(), uids.size(), assets.size(), imports.size(), game_dir])

	_check_pairs(scripts, uids, ".uid", "Godot 이 아직 임포트하지 않았다 (--import 실행 후 커밋할 것)")
	_check_pairs(assets, imports, ".import", "Godot 이 아직 임포트하지 않았다 (--import 실행 후 커밋할 것)")
	_check_orphans(uids, files, ".uid", "스크립트가 지워졌는데 uid 만 남았다")
	_check_orphans(imports, files, ".import", "자산이 지워졌는데 .import 만 남았다")
	_check_tracked(uids + imports, tracked, game_dir)

	if _fails.is_empty():
		print("PASS — 메타파일 %d개 전부 짝이 맞고 git 에 추적됨" % (uids.size() + imports.size()))
		quit(0)
	else:
		print("FAIL — %d건" % _fails.size())
		for f: String in _fails:
			print("  - " + f)
		quit(1)


# 규칙 1) 모든 원본에 짝이 되는 메타파일이 있는가.
func _check_pairs(sources: Array[String], metas: Array[String], suffix: String, hint: String) -> void:
	for s: String in sources:
		if not metas.has(s + suffix):
			_fail("%s 없음: %s — %s" % [suffix, s, hint])


# 규칙 2) 원본이 사라진 고아 메타파일이 없는가.
func _check_orphans(metas: Array[String], files: Array[String], suffix: String, hint: String) -> void:
	for m: String in metas:
		if not files.has(m.trim_suffix(suffix)):
			_fail("고아 %s: %s — %s (git rm 할 것)" % [suffix, m, hint])


# 규칙 3) 모든 메타파일이 git 에 추적되는가.
func _check_tracked(metas: Array[String], tracked: Array[String], game_dir: String) -> void:
	if tracked.is_empty():
		return  # git 자체가 실패한 경우. 위에서 이미 FAIL 로 잡았다.
	for m: String in metas:
		var rel := m.trim_prefix(game_dir + "/")
		if not tracked.has(rel):
			_fail("git 미추적: %s — 임포트 메타파일은 커밋하는 규칙이다 (git add 할 것)" % rel)


func _fail(msg: String) -> void:
	_fails.append(msg)


func _filter_suffix(files: Array[String], suffix: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in files:
		if f.ends_with(suffix):
			out.append(f)
	return out


# `.import` 이 생겨야 하는 자산 파일들. 메타파일 자신은 제외한다.
func _filter_imported_assets(files: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for f: String in files:
		if not f.ends_with(".import") and IMPORTED_EXTS.has(f.get_extension().to_lower()):
			out.append(f)
	return out


# `dir` 아래를 재귀로 훑어 모든 파일의 절대 경로를 모은다.
# res:// 대신 절대 경로로 훑는 이유: Godot 은 res:// 목록에서 임포트 메타파일류를
# 걸러 보여줄 수 있어서, 디스크에 실제로 뭐가 있는지를 봐야 한다.
func _collect(dir: String) -> Array[String]:
	var found: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		_fail("디렉터리를 열 수 없다: %s" % dir)
		return found
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):  # .godot 등 숨김 디렉터리는 건너뛴다
			name = d.get_next()
			continue
		var full := dir + "/" + name
		if d.current_is_dir():
			found.append_array(_collect(full))
		else:
			found.append(full)
		name = d.get_next()
	d.list_dir_end()
	return found


# game/ 기준 상대 경로로, git 이 추적 중인 파일 목록을 돌려준다.
func _git_tracked(game_dir: String) -> Array[String]:
	var out: Array = []
	var code := OS.execute("git", ["-C", game_dir, "ls-files"], out, true)
	if code != 0:
		_fail("git ls-files 실패 (종료코드 %d)" % code)
		return []
	var tracked: Array[String] = []
	for line: String in String(out[0]).split("\n"):
		var rel := line.strip_edges()
		if rel != "":
			tracked.append(rel)
	return tracked
