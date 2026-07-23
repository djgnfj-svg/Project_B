class_name MaterialDef
extends Resource
# 재료 정의 스키마 (core — 리드 전용). 개체는 data/materials/*.tres (projectb-rules §4).
# 강화(일반 재료)·제작(일반+핵심 재료)에 소비. 핵심 재료(is_core)는 보스 드랍 (GDD §6).

@export var id: String = ""            # data/materials/<id>.tres 파일명과 일치 — 드랍/인벤/레시피의 키
@export var display_name: String = ""
@export_multiline var description: String = ""  # 아이템 툴팁 설명(선택) — 비면 등급만 표시 (UI item_ui 헬퍼)
@export var icon: Texture2D            # 드랍 엔티티·인벤 표시 스프라이트 (도형 금지, rules §0)
@export var is_core: bool = false      # 핵심 재료(보스 드랍, 신장비 제작 게이트) 여부
@export var rarity: int = 0            # 0=일반(흰)·1=희귀(파랑)·2=핵심(금) — 드랍 등급 연출(feel)이 읽는다
