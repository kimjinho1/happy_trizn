# Trizmon — Spec (v0 draft)

> 진짜 포켓몬 클론 수준의 자체 IP 몬스터 RPG. Happy Trizn 의 장기 flagship 게임.
> 사내 게임 허브 안에 통합 — 모험 모드 / PvE 대결 / PvP 대결 3 가지 진입점.
>
> **이 문서는 spec 초안.** 코드 작성 전 review + 합의 위함. Sprint 분할은 마지막 섹션.

## 0. 라이선스 / IP

- **포켓몬 이름 / 디자인 / 음악 / 도감 / 기술 이름 그대로 가져오면 Nintendo IP 침해**. 사내용 토이라도 위험.
- 자체 IP "Trizmon" — 명칭 / 디자인 / 기술 이름 모두 자체 제작.
- AI 생성 이미지 = 자체 prompt 로 생성, 학습 모델이 포켓몬 스타일 흉내내도 ID 별 매핑은 자체.
- 영감 source 인정 — 메커니즘 (턴제 6vs6, 18 타입, 상성, IV/EV, 진화 등) 은 게임 컨벤션 차원으로 fair use. 단, brand asset 0.

## 1. 세계관 + 명명

- **세계관**: 사내 게임 허브 안의 가상 세계 "Triznia". 4개 도시 (각 도시 = Sprint 한 단위), 각 도시에 길드 (gym) 1개 + 트레이너 NPC 다수.
- **주인공**: 사용자 본인 닉네임. 첫 진입 시 시작 몬스터 3 종 중 1 선택.
- **목표**: 모든 길드 클리어 → 챔피언 도전 → 도감 완성 (collection completion) → PvP 랭크 상위.
- **이름 규칙**:
  - 종 (species) = "Trizmon" + 한 단어 (예: `Pyromon`, `Aquamon`, `Voltmon`, `Glacemon`)
  - 또는 한국어 wordplay (`불꽃이`, `물방울이`)
  - 자체 IP 강조 — Pikachu / Charizard 등 직접 reference 절대 금지

## 2. 타입 시스템 (18 종)

진짜 포켓몬 18 타입 그대로 컨벤션 사용 (게임 컨벤션). 타입 명은 한글:

```
일반 / 불 / 물 / 전기 / 풀 / 얼음 / 격투 / 독 / 땅 / 비행 /
에스퍼 / 벌레 / 바위 / 고스트 / 드래곤 / 악 / 강철 / 페어리
```

각 몬스터 = 1 또는 2 타입.

## 3. 상성 표 (간단 형태)

`damage_multiplier(attacker_type, defender_type) → 0.0 | 0.5 | 1.0 | 2.0`

| 공격 → 방어 | 일반 | 불 | 물 | 풀 | 전기 | 얼음 | 격투 | 독 | 땅 | 비행 | 에스퍼 | 벌레 | 바위 | 고스트 | 드래곤 | 악 | 강철 | 페어리 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 일반 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | ½ | 0 | 1 | 1 | ½ | 1 |
| 불 | 1 | ½ | ½ | 2 | 1 | 2 | 1 | 1 | 1 | 1 | 1 | 2 | ½ | 1 | ½ | 1 | 2 | 1 |
| 물 | 1 | 2 | ½ | ½ | 1 | 1 | 1 | 1 | 2 | 1 | 1 | 1 | 2 | 1 | ½ | 1 | 1 | 1 |
| 풀 | 1 | ½ | 2 | ½ | 1 | 1 | 1 | ½ | 2 | ½ | 1 | ½ | 2 | 1 | ½ | 1 | ½ | 1 |
| 전기 | 1 | 1 | 2 | ½ | ½ | 1 | 1 | 1 | 0 | 2 | 1 | 1 | 1 | 1 | ½ | 1 | 1 | 1 |
| 얼음 | 1 | ½ | ½ | 2 | 1 | ½ | 1 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 2 | 1 | ½ | 1 |
| 격투 | 2 | 1 | 1 | 1 | 1 | 2 | 1 | ½ | 1 | ½ | ½ | ½ | 2 | 0 | 1 | 2 | 2 | ½ |
| 독 | 1 | 1 | 1 | 2 | 1 | 1 | 1 | ½ | ½ | 1 | 1 | 1 | ½ | ½ | 1 | 1 | 0 | 2 |
| 땅 | 1 | 2 | 1 | ½ | 2 | 1 | 1 | 2 | 1 | 0 | 1 | ½ | 2 | 1 | 1 | 1 | 2 | 1 |
| 비행 | 1 | 1 | 1 | 2 | ½ | 1 | 2 | 1 | 1 | 1 | 1 | 2 | ½ | 1 | 1 | 1 | ½ | 1 |
| 에스퍼 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 1 | 1 | ½ | 1 | 1 | 1 | 1 | 0 | ½ | 1 |
| 벌레 | 1 | ½ | 1 | 2 | 1 | 1 | ½ | ½ | 1 | ½ | 2 | 1 | 1 | ½ | 1 | 2 | ½ | ½ |
| 바위 | 1 | 2 | 1 | 1 | 1 | 2 | ½ | 1 | ½ | 2 | 1 | 2 | 1 | 1 | 1 | 1 | ½ | 1 |
| 고스트 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 1 | 1 | 2 | 1 | ½ | 1 | 1 |
| 드래곤 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 1 | ½ | 0 |
| 악 | 1 | 1 | 1 | 1 | 1 | 1 | ½ | 1 | 1 | 1 | 2 | 1 | 1 | 2 | 1 | ½ | 1 | ½ |
| 강철 | 1 | ½ | ½ | 1 | ½ | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 1 | 1 | 1 | ½ | 2 |
| 페어리 | 1 | ½ | 1 | 1 | 1 | 1 | 2 | ½ | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | ½ | 1 |

표 데이터 = `lib/happy_trizn/trizmon/type_chart.ex` 의 const map.

2 타입 몬스터 다중 적용: `mult = type1_mult * type2_mult` (0/¼/½/1/2/4 가능).

## 4. Schema — 종 (species) vs 개체 (instance)

### 종 (Trizmon Species)

종 = 정적 데이터, DB seed 로 적재. 100 종 MVP 목표 (Sprint 단위로 추가).

```
species (
  id integer PK
  slug string unique  # "pyromon-001"
  name_ko string       # "불꽃이"
  name_en string       # "Pyromon"
  type1 string         # "fire"
  type2 string nullable
  base_hp integer
  base_atk integer
  base_def integer
  base_spa integer     # 특수공격
  base_spd integer     # 특수방어
  base_spe integer     # 속도
  catch_rate integer   # 1-255
  exp_curve string     # "fast" / "medium_fast" / "medium_slow" / "slow"
  height_m float
  weight_kg float
  pokedex_text string  # 도감 설명 한 단락
  evolves_to_id integer nullable FK species
  evolves_at_level integer nullable
  evolution_method string nullable  # "level" / "stone_fire" / "trade" / "friendship"
  image_url string     # AI 생성 PNG. assets/static/trizmon/<slug>.png
  inserted_at, updated_at
)
```

### 개체 (Trizmon Instance)

사용자가 보유한 한 마리.

```
trizmon_instances (
  id binary_id PK
  user_id binary_id FK
  species_id integer FK species
  nickname string nullable
  level integer 1..100
  exp integer
  iv_hp integer 0..31
  iv_atk integer 0..31
  iv_def integer 0..31
  iv_spa integer 0..31
  iv_spd integer 0..31
  iv_spe integer 0..31
  ev_hp integer 0..252  # max sum 510
  ev_atk integer 0..252
  ev_def integer 0..252
  ev_spa integer 0..252
  ev_spd integer 0..252
  ev_spe integer 0..252
  nature string         # 25 종 (atk+/def-, spe+/spa- 등)
  ability string nullable  # 추후 — v0 는 nil
  current_hp integer    # 배틀 중 HP. 패배 시 0, 회복하면 max
  status string nullable  # "burn" / "poison" / "paralysis" / "freeze" / "sleep"
  status_turns integer  # 잠/혼란 같은 turn count
  move1_id integer FK moves
  move2_id integer FK moves
  move3_id integer FK moves
  move4_id integer FK moves
  move1_pp integer
  move2_pp integer
  move3_pp integer
  move4_pp integer
  caught_at utc_datetime
  caught_location string  # "초원" / "동굴 입구" 등
  is_starter boolean default false
  in_party_slot integer nullable  # 1..6 = 현재 파티, nil = 보관함
  inserted_at, updated_at
)

INDEX (user_id, in_party_slot)
INDEX (user_id, species_id)
```

### Stats 계산 공식 (포켓몬 컨벤션)

```
HP = floor((2 * base + IV + ev/4) * level / 100) + level + 10
기타 = (floor((2 * base + IV + ev/4) * level / 100) + 5) * nature_modifier
```

`nature_modifier`: stat 1개 1.1배, 다른 stat 1개 0.9배 (HP 제외).

## 5. 기술 (Move) Schema

```
moves (
  id integer PK
  slug string unique     # "ember-001"
  name_ko string          # "불씨"
  type string             # "fire"
  category string         # "physical" / "special" / "status"
  power integer nullable  # 변화기는 nil
  accuracy integer 1..100 nullable  # nil = 100% 명중
  pp integer 5..40        # 사용 횟수
  priority integer -7..5
  effect_code string nullable  # "burn_10" "para_10" "stat_atk_user_+1" 등
  description string
  inserted_at, updated_at
)
```

100 기술 MVP. species 마다 학습 가능 기술 list 별도 table:

```
species_moves (
  species_id integer FK
  move_id integer FK
  learn_level integer nullable  # nil = TM/HM
  learn_method string  # "level" / "tm" / "egg" / "tutor"
  PK (species_id, move_id, learn_method)
)
```

## 6. 상태 이상

| 이상 | 효과 |
|---|---|
| **화상 (burn)** | 매 턴 최대 HP 1/16 감소. 물리 공격력 절반 |
| **마비 (paralysis)** | 매 턴 25% 확률 행동 X. 속도 50% |
| **독 (poison)** | 매 턴 최대 HP 1/8 감소 |
| **맹독 (badly_poison)** | 매 턴 1/16 시작, 턴마다 1/16 누적 |
| **잠 (sleep)** | 1-3 턴 행동 X, 깨어나면 행동 가능 |
| **동결 (freeze)** | 행동 X, 매 턴 20% 확률 풀림 |
| **혼란 (confuse)** | 1-4 턴, 33% 확률 자기 자신 공격 |

배틀 종료 후 자동 회복? — burn/poison 등 영구. 잠/혼란 = 배틀 끝나면 풀림. 정확 정책 별도 결정.

## 7. 배틀 시스템

### 진행

1. 양쪽이 행동 선택 (기술 / 교체 / 도구 / 도망)
2. **우선도 결정**: priority → speed → tie 시 random
3. 선택한 행동 순차 실행
4. 매 턴 종료: 상태 이상 dmg / 회복 / 카운터
5. 한 쪽 6 마리 모두 KO = 패배

### 데미지 공식 (포켓몬 컨벤션)

```
damage = floor(
  ((2 * level / 5 + 2) * power * (atk / def) / 50 + 2)
  * stab            # same-type attack bonus 1.5
  * type_eff        # 0 / ¼ / ½ / 1 / 2 / 4
  * crit            # 1.5 (1/24 확률, 변화기 X)
  * random          # 0.85~1.0
  * burn_mult       # 화상 + 물리 = 0.5
)
```

특수기는 spa/spd 사용. crit 시 보정 무시.

### Crit / Miss

- 기본 crit 확률 = 1/24
- accuracy = move 의 accuracy * 명중률 단계 / 회피율 단계
- 빗나감 표시

### 배틀 모드 (3vs3 / 6vs6 선택)

- **PvE / PvP**: 방 생성 시 `battle_format: "3v3" | "6v6"` 선택. 3v3 = 빠른 매치, 6v6 = 풀배틀.
- **PvE 일반 트레이너 (모험 모드 NPC)**: 트레이너 마다 정해진 format (NPC 데이터에 명시).
- **모험 야생 만남**: 1 vs 1 (야생 1마리 vs 사용자 파티 첫 마리). format 무관.
- 1vs1 모드 = X (포켓몬 컨벤션 유지, 너무 단조).

## 8. 레벨 / 경험치 / 진화

### 경험치 곡선 (4 종, 포켓몬 컨벤션)

| 곡선 | 100lv 도달 exp |
|---|---|
| fast | 800,000 |
| medium_fast | 1,000,000 |
| medium_slow | 1,059,860 |
| slow | 1,250,000 |

### 진화 조건

- **레벨 도달** — 가장 흔함 (16, 32, 36 등)
- **돌 사용** — 불꽃의 돌 / 물의 돌 / 천둥의 돌 / 풀의 돌 / 어둠의 돌 / 빛의 돌
- **친밀도** — 최대 친밀도 + 레벨업
- **트레이드** — 사용자 사이 교환 시 진화 (Sprint 5c-late)

## 9. 모험 모드 (Adventure)

`/play/trizmon` (싱글) — 진입 시 사용자 본인 progress.

### 맵 시스템 (HTML5 Canvas tile-based grid) ✅

- **방식**: tile-based 2D grid 맵. 각 도시 / 길 / 동굴 = 1 맵 = 30x20 정도 grid
- **렌더**: HTML5 Canvas — Pacman 패턴 재사용. tile sprite 32x32 → 맵 = 960x640 px.
- **확장성**: 향후 sprite animation (4-frame walk cycle), parallax background, lighting / weather shader, spritesheet 통합 모두 가능.
- **이동**: 화살표 / WASD 1 칸씩 grid step. 시각적으로 smooth 보간 (CSS transition or canvas tween, ~150ms).
- **만남**: 풀밭 / 동굴 tile 위 = 매 step 8% 확률 야생 인카운터.
- **NPC**: tile 위 정해진 위치 — 말 걸면 대화 / 트레이너 배틀 / 힌트.
- **포커스 / 대화**: LiveView 안에 dialog overlay (HTML, canvas 위 layer).
- **데이터 흐름**: LiveView 가 tile data + entity (player / NPC / 인카운터 트리거) JSON 으로 push → JS canvas 가 render. 사용자 입력 = LiveView event → server move + 충돌 체크 → 새 state push.

### 진행 곡선

| Sprint | Region | 길드 | 출현 species | level cap |
|---|---|---|---|---|
| 5c-2 | 시작 마을 + 1 도시 | 1 | 15 | 20 |
| 5c-3 | 2 도시 | 1 | +20 | 35 |
| 5c-4 | 3 도시 | 1 | +20 | 50 |
| 5c-5 | 4 도시 (챔피언) | 1 | +20 | 65 |
| 5c-6 | 후기 region | 0 | +25 | 100 |

### Save / 체크포인트

- 자동 저장 — 각 모험 step 후 LV terminate / interval. `trizmon_saves` 테이블.
- 사용자 한 명 = save slot 1 (단순화)

```
trizmon_saves (
  user_id binary_id PK
  current_map string         # "starting_town"
  player_x integer
  player_y integer
  badges integer             # bitmask 길드 클리어
  pokedex_seen integer[]     # 본 species id
  pokedex_caught integer[]   # 잡은 species id
  money integer              # 인게임 화폐
  last_played_at utc_datetime
  inserted_at, updated_at
)
```

## 10. PvE 대결 모드

`/play/trizmon-pve` (싱글) — 모험 진행과 무관, 빠른 배틀.

- **랜덤 매치**: CPU 6 마리 random pick (사용자 level cap 기준)
- **토너먼트**: 8 트레이너 연속 (회복 X)
- **연습 (난이도 선택)**: easy / normal / hard — CPU AI 기술 선택 정밀도 차이

CPU AI:
- **easy**: random move
- **normal**: type 효과 우선 + max dmg expectation
- **hard**: 상태 이상 / 교체 / setup move 활용 (advanced — 후기 Sprint)

## 11. PvP 대결 모드

`/game/trizmon-pvp/<room_id>` (멀티) — 기존 멀티 게임 패턴 + **친구 끼리만**.

- **친구 매칭만**: 방 생성 시 `friend_only: true` 강제. 친구 list 에 있는 사람만 입장 가능. URL 직접 접근해도 거부.
- 매치 진입:
  1. lobby 친구 list 에서 "Trizmon 도전" 버튼 클릭 (기존 게임 초대 패턴 재사용)
  2. DM 자동 발송 — "Trizmon PvP 도전 (3v3 / 6v6)" + URL
  3. 친구 클릭 → 방 입장 → 둘 다 파티 send
- 호스트 + 게스트 1명 = 1대1 트레이너 배틀 (3vs3 또는 6vs6)
- 양쪽 진입 후 파티 자동 send (모험 모드 in_party_slot = 1..N 마리)
- 둘 다 파티 0 마리면 reject (모험 진행 X 사용자 = 시작 못 함)
- match_results 누적 (이미 있음)
- 랭크 시스템 (Sprint 5c-late): ELO 1000 시작, 승/패에 따라. 친구 끼리만 매칭이라 ELO 가 적은 사람과만 의미있음 — 후기 정책 결정 (예: 회사 전체 leaderboard, 개인 ELO 는 친구 vs 게임 만 반영)

## 12. 도감

`/me/trizmon-pokedex` 또는 모험 모드 안 메뉴.

- 본 species (만남 + 미잡음) vs 잡은 species 구분
- species 클릭 = 정보 (name, type, 도감 설명, 이미지, 진화 트리, 학습 기술)
- 잡은 종 = 보유 instance list (level / nickname / status)

## 13. 트레이드

Sprint 5c-late.

- 사용자 A 가 instance 선택 → B 에게 offer
- B 수락 → 둘 다 commit → DB transaction 으로 user_id swap
- 트레이드 진화 — swap 후 진화 발동

## 14. AI 이미지 파이프라인

### 모델 / 스타일

- **모델 = Gemini Imagen** (Vertex AI) ✅ 사용자 결정.
- **인증**: GCP Service Account JSON. 개발자 본인 GCP 프로젝트 필요. 비용 ≈ $0.04/이미지 × 100 종 = ~$4 (1회 batch).
- **스타일 통일**: 동일 prompt prefix — "pixel art, retro RPG monster, 64x64, transparent background, vibrant colors, simple silhouette, original design inspired by classic monster RPG games"
- **per-species prompt**: type / 컨셉 키워드 추가. 예: `Pyromon (불꽃이) — fire dragon hatchling, orange, two horns, small wings`
- **검수**: admin 페이지 (`/admin/trizmon/images`) 에서 1차 승인. 안 좋으면 재생성 트리거.
- **batch script**: `priv/scripts/generate_trizmon_images.sh` — species seed 의 prompt 자동 생성 + Imagen API 호출 + PNG 저장.

### 저장

- 생성 PNG = `assets/static/images/trizmon/<species_slug>.png`
- DB species.image_url = `/images/trizmon/<species_slug>.png`
- 진화 단계 별로 다른 PNG (3 단 진화 = 3 이미지)
- 라이선스 안전 디렉토리 표기 + 출처 metadata 별도 텍스트 파일

### Pipeline Sprint

- **Sprint 5c-1.5 (이미지 작업)**: bash script + curl 로 model API 호출. species 100 종 prompt 자동 생성 + 이미지 download. 사용자 검수.

## 15. DB Schema 정리

### 신규 마이그레이션 (Sprint 5c-1)

1. `species` (정적, seed 로 채움)
2. `moves` (정적, seed)
3. `species_moves` (정적, seed)
4. `trizmon_instances` (사용자 데이터)
5. `trizmon_saves` (모험 진행 저장)
6. `trizmon_pokedex` (선택 — pokedex_seen/caught 를 별도 row 로 normalize 가능. 또는 saves 의 array 컬럼 재사용)
7. `trizmon_battles` (PvE/PvP 배틀 로그 — match_results 와 통합 또는 별도)

### Seed 데이터 위치

- `priv/repo/seeds/trizmon_species.exs` — 100 종 def
- `priv/repo/seeds/trizmon_moves.exs` — 100 기술 def
- `priv/repo/seeds/trizmon_species_moves.exs` — 학습 표
- `priv/repo/seeds/trizmon_npcs.exs` — NPC 정의 (대화, 트레이너 파티)
- `priv/repo/seeds/trizmon_maps/<map_id>.json` — 맵 tile data

`mix run priv/repo/seeds/seed_trizmon.exs` 로 일괄 import.

## 16. 게임 엔진 모듈 구조

```
lib/happy_trizn/trizmon/
├── type_chart.ex           # 18x18 mult map + dmg mult 계산
├── stats.ex                # HP / atk / spa 계산 공식, nature
├── exp_curves.ex           # 4 곡선 → exp_for_level/2
├── battle/
│   ├── engine.ex           # 한 턴 처리 (action 받음 → state 갱신)
│   ├── turn.ex             # priority/speed 결정
│   ├── damage.ex           # 데미지 공식 + crit + miss
│   ├── status.ex           # 상태 이상 적용 / 매 턴 처리
│   └── ai.ex               # CPU 행동 선택 (easy/normal/hard)
├── moves.ex                # move effect_code dispatcher
├── species.ex              # 종 lookup + 진화 트리
├── instance.ex             # 개체 stats 계산 + 레벨업 + 학습
├── pokedex.ex              # 본/잡은 등록
├── world/                  # 모험 모드
│   ├── map.ex              # tile data, 충돌, 만남 trigger
│   ├── encounter.ex        # 야생 인카운터 확률 + species 선택
│   ├── npc.ex              # NPC 대화 / 트레이너 배틀
│   └── save.ex             # save / load
└── trade.ex                # 사용자 사이 trade
```

기존 `lib/happy_trizn/games/` 패턴과 비슷 — 단, Trizmon 은 너무 큼 → 별도 폴더.

게임 모듈 (`GameBehaviour`) 통합:
- `lib/happy_trizn/games/trizmon_pve.ex` — PvE 단일
- `lib/happy_trizn/games/trizmon_pvp.ex` — PvP 멀티
- `lib/happy_trizn/games/trizmon_adventure.ex` — 모험 (싱글, 자체 tick)

3 모듈 모두 `HappyTrizn.Trizmon.Battle.Engine` 등 core 재사용.

## 17. UI / LiveView 구조

```
lib/happy_trizn_web/live/
├── trizmon_battle_live.ex      # 배틀 화면 (PvE/PvP 공용)
├── trizmon_adventure_live.ex   # 모험 모드 (canvas + dialog)
├── trizmon_pokedex_live.ex     # 도감
├── trizmon_party_live.ex       # 파티 편성 + 보관함
└── trizmon_trade_live.ex       # 트레이드 (Sprint late)
```

배틀 UI:
- 양쪽 몬스터 sprite + HP bar + 기술 4개 button
- 텍스트 로그 (turn 별 "Pyromon 의 불씨!" "효과는 굉장했다!" 등)
- 교체 버튼

## 18. Sprint 분할 (장기 plan)

| Sprint | 범위 | 주요 산출물 |
|---|---|---|
| **5c-1 인프라** | DB schema + type_chart + stats + 1 종 + 1 기술 + dmg 계산 함수 | 마이그레이션, type_chart.ex, stats.ex, smoke test |
| **5c-1.5 AI 이미지** | 100 종 prompt 작성 + 이미지 batch generate + 사용자 검수 | assets/static/images/trizmon/*.png |
| **5c-2 PvE MVP** | 6 vs CPU 6 배틀, 기본 기술 30개, 종 30 | trizmon_pve.ex, battle.engine, battle UI |
| **5c-3 모험 region 1** | 시작 마을 + 1 도시, 야생 인카운터, 1 길드 | adventure_live.ex, world/map.ex, save.ex |
| **5c-4 모험 region 2-3** | 추가 도시 + 트레이너 다양화 | seed 확장 |
| **5c-5 PvP** | 1v1 6vs6 멀티 배틀 | trizmon_pvp.ex (GameSession) |
| **5c-6 도감 + 진화** | pokedex_live, 진화 시스템, 친밀도 | pokedex.ex, instance.ex evolve |
| **5c-7 트레이드** | 사용자 사이 instance 교환 | trade.ex, UI |
| **5c-8 챔피언 / 후반** | 4 길드 + 챔피언, level cap 100 | seed |
| **5c-9 PvP 랭크** | ELO + 시즌 | rank_table |
| **5c-10 polish** | balance, sound, animation | — |

각 Sprint = PR 1개 또는 2개. 5c-1 부터 차근차근.

## 19. 시작 체크리스트 (Sprint 5c-1)

- [x] 본 spec review + 합의 ✅
- [x] 자체 IP 명 = "Trizmon" ✅
- [x] AI 이미지 모델 = Gemini Imagen ✅
- [ ] 마이그레이션 6개 작성 (species / moves / species_moves / instances / saves / battles)
- [ ] `lib/happy_trizn/trizmon/type_chart.ex` (18×18 const map)
- [ ] `lib/happy_trizn/trizmon/stats.ex` (HP / 기타 stat 계산 공식 + nature)
- [ ] `lib/happy_trizn/trizmon/exp_curves.ex` (4 곡선)
- [ ] `lib/happy_trizn/trizmon/battle/damage.ex` (데미지 공식)
- [ ] 1 종 (시작 몬스터 "불꽃이"), 1 기술 ("몸통 박치기") seed 로 smoke test
- [ ] type_chart + stats + damage unit test
- [ ] CLAUDE.md 갱신 (없어진 상태) — Trizmon 작업 가이드 추가 (별도 PR 추천)

## 20. 확장 가능성 (장기)

- **사운드** — 배틀 SFX, BGM (자체 제작 / 무료 OFL 음원)
- **사회 기능** — 친구 trizmon party 보기, 친구와 PvP 매치
- **이벤트 / 시즌** — 한정 species, 시즌 PvP 랭킹
- **모바일 반응형** — 터치 컨트롤
- **번역** — 영어 i18n
- **mod 시스템** — 사용자 정의 species (관리자 승인 후 게임 입장)

## 21. 알려진 위험

| 위험 | 확률 | 대응 |
|---|---|---|
| AI 이미지 일관성 X | 높음 | 같은 prompt prefix + reference image 활용 + 사용자 검수 |
| Nintendo IP 침해 의심 | 중간 | 자체 명/디자인 엄수, "Trizmon-inspired by retro RPG" 명시 |
| Balance hell | 매우 높음 | Sprint 5c-2 에 30 종 30 기술만 → playtest → 조정 후 확장 |
| DB 폭증 | 중간 | trizmon_instances 사용자당 1000 마리 cap, 보관함 페이지네이션 |
| 모험 진행 cheating | 낮음 | save 는 server-side, client-side input 검증 |
| AI image API cost | 중간 | 100 이미지 1회 generate (그 후 정적). 사용자 input 으로 재생성은 admin only |

---

이 spec 합의 후 **Sprint 5c-1 (인프라)** 부터 코드 작업 진행.

## 22. 결정 사항 (사용자 합의 완료)

1. **자체 IP 명 = "Trizmon"** ✅
2. **AI 이미지 모델 = Gemini Imagen** ✅ (Sprint 5c-1.5 에서 batch 생성)
3. **모험 맵 = HTML5 Canvas tile-based grid** ✅ (Pacman 패턴 재사용. 게임 렌더링 표준 + 향후 sprite animation / parallax / shader 확장 자유로움. SVG/ASCII 보다 보기 좋음 + 개발 확장성 우수)
4. **언어 우선 = 한글** ✅ (species name / move name / 도감 텍스트 / NPC 대사 모두 한글 first. 영문 i18n 은 future Sprint)
5. **배틀 모드 = 3vs3 / 6vs6 선택 가능** ✅ (방 만들 때 옵션 선택. PvE 도 동일. 1vs1 X — 포켓몬 컨벤션 유지)
6. **친구 끼리만 PvP** ✅ (lobby 의 PvP 매칭 = friends_list 에 있는 사람만 가능. 친구 추천 / 초대 통한 진입 only. 길드 시스템 X — 단순화)

## 23. 결정 사항 후속 — spec 본문 영향 정리

### 배틀 모드 (3vs3 / 6vs6 선택)

- 방 생성 시 `battle_format: "3v3" | "6v6"` 옵션 (PvP)
- PvE 진입 시 같은 picker
- 모험 모드 야생 만남 = 1v1 그대로 (사용자 파티 첫 마리 vs 야생)
- in_party_slot 컬럼 = 1..6 그대로 유지. 3v3 모드는 첫 3 마리만 사용

### 친구 PvP (친구만 매칭)

- 매치 흐름:
  1. lobby 친구 list 에서 PvP 도전 button (게임 초대 패턴 재사용)
  2. DM 자동 발송 — "Trizmon PvP 도전!" + URL `/game/trizmon-pvp/<room_id>?format=6v6`
  3. 친구 클릭 → 방 입장 → 둘 다 파티 send → 배틀
- 방 생성 시 `friend_only: true` 강제 (Trizmon PvP)
- 친구 아닌 사용자가 URL 알아도 입장 거부

### Canvas 맵

- `assets/js/games/trizmon-adventure/canvas.js` (Pacman 패턴 참고)
- tile sprite 32x32 → 큰 맵 = 30x20 = 960x640 px canvas
- LiveView 가 tile data + entity (player / NPC / 야생 인카운터 트리거) JSON push → JS canvas 가 render
- 사용자 입력 = 화살표 / WASD → LiveView event → server move + 충돌 체크 → 새 state push

### 한글 우선 표시

- species/move name = 한글 first (DB `name_ko` 필수, `name_en` optional)
- 도감 텍스트 = 한글 first
- NPC 대사 = 한글 first
- 향후 Sprint 5c-late or future Sprint 5d = 영문 i18n + locale switcher

### Gemini Imagen 파이프라인 상세

- Provider: Google Cloud Vertex AI Imagen API
- 인증: GCP Service Account JSON (개발자 본인이 GCP 프로젝트 생성, $0.04/이미지 4 변형 = 100 종 × 0.04 ≈ $4)
- 호출: `bash priv/scripts/generate_trizmon_images.sh` — species seed 의 prompt 자동 생성 + Imagen API 호출 + PNG 저장
- 검수: 생성 후 사용자가 admin 페이지 (`/admin/trizmon/images`) 에서 종별 1차 승인 — 안 좋으면 재생성 트리거
- 결과 저장: `assets/static/images/trizmon/<species_slug>.png`
