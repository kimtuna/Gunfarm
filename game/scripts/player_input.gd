extends RefCounted

## 플레이어가 한 틱 동안 보내는 입력 한 벌.
##
## **이게 나중에 네트워크로 오갈 값이다** — docs/DESIGN.md 「서버 권위 / 클라이언트
## 신뢰」의 "클라이언트는 위치를 보내지 않는다. 입력(이동 방향 / 조준 각도 / 버튼)만
## 보낸다" 그대로다. 그래서 이동 방향과 조준 각도를 **한 구조체에 같이** 담는다:
## 둘은 같은 순간의 입력이라 따로 보내면 서버에서 어긋난 짝으로 시뮬레이션된다.
##
## 조준을 **화면 좌표가 아니라 각도로** 담는 이유도 같다 — 마우스 좌표는 해상도와
## 카메라에 따라 클라이언트마다 다르지만, 각도는 서버와 모든 클라이언트에서 같은
## 값이다 (docs/DESIGN.md 「조작」).

## 기본 조준 각도 = 아래쪽. 캐릭터가 처음 설 때 보는 방향이다.
## (Godot 2D 좌표계는 y 가 아래로 커져서 아래가 +PI/2 다.)
const AIM_DOWN := PI * 0.5

## WASD 두 축. 각 성분은 -1 / 0 / 1 이다.
var move := Vector2i.ZERO

## 조준 각도(라디안). 0 = 오른쪽, +PI/2 = 아래, PI = 왼쪽, -PI/2 = 위.
## **이동 방향과 무관하다** — 왼쪽으로 걸으면서 오른쪽을 겨눌 수 있다(게걸음).
var aim_angle := AIM_DOWN

## 지금 손에 든 핫바 칸(0~8). **아이템 id 가 아니라 칸 번호다** — 서버는 그 칸에
## 무엇이 들어 있는지 자기 인벤토리에서 직접 보므로, 클라이언트가 "나는 도끼를
## 들었다"고 주장할 자리가 없다 (docs/DESIGN.md 「서버 권위」).
var hotbar := 0

## 이 틱에 좌클릭했는가 = 손에 든 도구를 쓴다 (docs/DESIGN.md 「조작」).
## **누른 순간만 true 인 버튼**이고, 실제로 무엇이 일어나는지(모션 재생·대상 판정)는
## 이 값을 받은 코어가 정한다.
var use := false


func _init(move_axes: Vector2i = Vector2i.ZERO, aim: float = AIM_DOWN,
		hotbar_slot: int = 0, use_pressed: bool = false) -> void:
	move = move_axes
	aim_angle = aim
	hotbar = hotbar_slot
	use = use_pressed
