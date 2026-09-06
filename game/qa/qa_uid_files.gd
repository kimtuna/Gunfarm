extends SceneTree

# 자체 QA — Godot 이 스크립트마다 만드는 `*.gd.uid` 파일의 관리 규칙 검증.
#
# 규칙 (2026-09-06 결정, 근거는 CLAUDE.md 「git」 참고): `.uid` 는 **커밋한다**.
#   1) 모든 `.gd` 옆에 짝이 되는 `.gd.uid` 가 있다.
#   2) 스크립트가 지워졌는데 남은 고아 `.gd.uid` 가 없다.
#   3) 모든 `.gd.uid` 가 git 에 추적되고 있다 (매 바퀴 untracked 로 쌓이지 않는다).
#
# 새 스크립트를 만든 바퀴는 이걸 돌려서 uid 를 빠뜨리지 않았는지 확인한다.
#
# 실행:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
#     --script qa/qa_uid_files.gd > /tmp/qa_uid.log 2>&1; echo $?

var _fails: Array[String] = []

func _initialize() -> void:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")

	var scripts := _collect(game_dir, ".gd")
	var uids := _collect(game_dir, ".gd.uid")
	print("스크립트 %d개 / uid %d개 (기준 디렉터리: %s)" % [scripts.size(), uids.size(), game_dir])

	# 1) 모든 .gd 에 짝이 되는 .uid 가 있는가
	for s: String in scripts:
		if not uids.has(s + ".uid"):
			_fail("uid 없음: %s — Godot 이 아직 임포트하지 않았다 (--import 실행 후 커밋할 것)" % s)

	# 2) 고아 .uid 가 없는가
	for u: String in uids:
		if not scripts.has(u.trim_suffix(".uid")):
			_fail("고아 uid: %s — 스크립트가 지워졌는데 uid 만 남았다 (git rm 할 것)" % u)

	# 3) 모든 .uid 가 git 에 추적되는가
	var tracked := _git_tracked_uids(game_dir)
	if tracked.is_empty():
		_fail("git ls-files 가 uid 를 하나도 못 찾았다 — git 실행 자체가 실패했을 수 있다")
	else:
		for u: String in uids:
			var rel := u.trim_prefix(game_dir + "/")
			if not tracked.has(rel):
				_fail("git 미추적: %s — `.uid` 는 커밋하는 규칙이다 (git add 할 것)" % rel)

	if _fails.is_empty():
		print("PASS — uid %d개 전부 짝이 맞고 git 에 추적됨" % uids.size())
		quit(0)
	else:
		print("FAIL — %d건" % _fails.size())
		for f: String in _fails:
			print("  - " + f)
		quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)


# `dir` 아래를 재귀로 훑어 `suffix` 로 끝나는 파일의 절대 경로를 모은다.
# res:// 대신 절대 경로로 훑는 이유: Godot 은 res:// 목록에서 임포트 메타파일류를
# 걸러 보여줄 수 있어서, 디스크에 실제로 뭐가 있는지를 봐야 한다.
func _collect(dir: String, suffix: String) -> Array[String]:
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
			found.append_array(_collect(full, suffix))
		elif name.ends_with(suffix):
			found.append(full)
		name = d.get_next()
	d.list_dir_end()
	return found


# game/ 기준 상대 경로로, git 이 추적 중인 .gd.uid 목록을 돌려준다.
func _git_tracked_uids(game_dir: String) -> Array[String]:
	var out: Array = []
	var code := OS.execute("git", ["-C", game_dir, "ls-files"], out, true)
	if code != 0:
		_fail("git ls-files 실패 (종료코드 %d)" % code)
		return []
	var tracked: Array[String] = []
	for line: String in String(out[0]).split("\n"):
		var rel := line.strip_edges()
		if rel.ends_with(".gd.uid"):
			tracked.append(rel)
	return tracked
