---
name: procedural-generation
description: 절차적 생성을 구현할 때 사용한다 — Godot 4.3+에서 노이즈 기반 지형, BSP 던전, 셀룰러 오토마타 동굴, 웨이브 함수 붕괴(WFC), 시드 기반 난수
---

# Godot 4.3+의 절차적 생성

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** TileMapLayer 사용은 **2d-essentials**, 3D 지형 메시는 **3d-essentials**, 벡터와 트랜스폼은 **math-essentials**, 청크 로딩과 성능은 **godot-optimization**을 참고하라.

---

## 1. 시드 기반 난수

재현 가능한 생성을 위해 항상 시드를 사용하라. 이렇게 하면 공유 가능한 시드, 리플레이, 결정론적 테스트가 가능해진다.

### GDScript

```gdscript
# RandomNumberGenerator — per-instance, seedable
var rng := RandomNumberGenerator.new()

func generate_level(level_seed: int) -> void:
    rng.seed = level_seed

    var width: int = rng.randi_range(20, 40)
    var height: int = rng.randi_range(15, 30)
    var enemy_count: int = rng.randi_range(3, 8)
    var treasure_chance: float = rng.randf_range(0.05, 0.15)

# AVOID: Global randf()/randi() — not reproducible across calls
# USE: rng.randf(), rng.randi(), rng.randf_range(), rng.randi_range()
```

### C#

```csharp
private RandomNumberGenerator _rng = new();

public void GenerateLevel(ulong levelSeed)
{
    _rng.Seed = levelSeed;

    int width = _rng.RandiRange(20, 40);
    int height = _rng.RandiRange(15, 30);
    int enemyCount = _rng.RandiRange(3, 8);
    float treasureChance = _rng.RandfRange(0.05f, 0.15f);
}
```

> **팁:** 공유 가능한 레벨 코드를 위해 문자열로부터 시드를 생성하라: `var seed: int = "MyLevel".hash()`

---

## 2. 노이즈 기반 생성 (FastNoiseLite)

높이 맵, 바이옴 분포, 2D 지형에는 `FastNoiseLite`를 쓴다. 핵심 파라미터: `noise_type`(Perlin / Simplex / Cellular / Value), `frequency`(낮을수록 큰 특징), `seed`. 지형의 경우 각 타일 좌표에서 노이즈를 샘플링하고 그 값을 임계 처리해 타일을 고른다.
---

## 3. BSP 던전 생성

이진 공간 분할(Binary Space Partitioning)은 사각형을 더 작은 사각형으로 재귀적으로 분할하고, 각 리프 안에 방을 파낸 뒤, 형제 노드들을 복도로 연결한다. 그리드에 정렬된 방 기반 던전(로그라이크를 떠올려라)을 만든다.
---

## 4. 셀룰러 오토마타 (동굴 생성)

그리드를 약 45% 밀도로 무작위 벽/바닥으로 채운 뒤, "이웃 8칸 중 5칸 이상이 벽이면 그 칸도 벽이 된다"를 4~5회 반복한다. 그 결과 유기적인 동굴 형태가 나온다 — 직선 복도가 없다.
---

## 5. 웨이브 함수 붕괴 (WFC)

WFC는 제약 해결기다: 인접 규칙이 있는 타일 세트가 주어지면, 엔트로피가 가장 낮은 칸을 골라 유효한 타일로 붕괴시키고, 제약을 전파하며, 반복한다. 타일 규칙을 지키는 출력을 만들지만 구현이 만만치 않다.
---

## 6. 흔한 함정

| 증상 | 원인 | 해결 |
|---------|-------|-----|
| 매번 같은 레벨 | RNG에 시드를 안 줌 | 생성 전에 `rng.seed`를 설정하라 |
| 플랫폼마다 결과가 다름 | 전역 `randf()` / `randi()` 사용 | 전용 `RandomNumberGenerator` 인스턴스를 써라 |
| 노이즈가 각져 보임 | frequency가 너무 높음 | `frequency`를 낮춰라 (0.01–0.05 시도) |
| 동굴이 전부 벽이거나 전부 바닥 | `fill_chance`가 너무 극단적이거나 반복이 너무 적음 | fill_chance 0.40–0.50, 반복 4–6회 사용 |
| BSP 방이 겹침 | 분할 위치가 가장자리에 너무 가까움 | 분할 계산에 `min_room_size` 여유를 확보하라 |
| WFC 모순(유효한 타일 없음) | 인접 규칙이 너무 빡빡함 | 허용 이웃을 늘리거나 백트래킹을 구현하라 |
| 생성이 너무 오래 걸림 | 전체 맵을 한 프레임에 처리 | `await get_tree().process_frame`으로 여러 프레임에 분산하거나 스레드를 써라 |

---

## 7. 구현 체크리스트

- [ ] 모든 생성이 시드 가능한 `RandomNumberGenerator`를 쓰고, 전역 `randf()`/`randi()`는 절대 안 쓴다
- [ ] 레벨을 재현할 수 있도록 시드가 저장 데이터와 함께 보관된다
- [ ] `FastNoiseLite`의 frequency와 octaves가 게임의 타일/월드 스케일에 맞게 튜닝돼 있다
- [ ] 큰 생성 작업은 프리징을 피하기 위해 여러 프레임에 분산하거나 스레드에서 돈다
- [ ] 생성된 TileMapLayer 콘텐츠는 가능하면 지형 오토타일링을 쓴다(하드코딩된 타일 좌표가 아니라)
- [ ] BSP 던전은 마무리 전에 모든 방이 연결됐는지 검증한다
- [ ] 동굴 생성은 핵심 지점 간 도달 가능성을 보장하기 위해 flood-fill을 돌린다
- [ ] 플레이어 스폰 지점이 벽 안이 아니라 바닥 타일 위인지 검증한다
