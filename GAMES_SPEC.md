# Games Spec — Jstris 수준 본격 기획

각 멀티 게임의 본격 spec. 현재 stub 또는 minimal 구현된 게임을 **Jstris 등 표준 게임 수준**으로 끌어올린 후속 작업 기획안.

이 문서는 **각 게임 PR 시 참조**해서 빠진 기능 / 옵션 트래킹.

## 목차

- [공통 — 사용자 게임 옵션](#공통--사용자-게임-옵션)
- [Tetris (Jstris 모방)](#tetris-jstris-모방)
- [Bomberman](#bomberman)
- [Skribbl](#skribbl)
- [Snake.io](#snakeio)
- [2048](#2048)
- [Minesweeper](#minesweeper)
- [Pac-Man](#pac-man)
- [DB 스키마](#db-스키마)
- [구현 순서](#구현-순서)

---

## 공통 — 사용자 게임 옵션

각 사용자가 게임마다 자기 옵션 저장. 로그인 안 한 게스트는 default + localStorage.

### Schema

```
user_game_settings
- id binary_id PK
- user_id FK users (cascade delete)
- game_type string(32) — "tetris", "bomberman", ...
- key_bindings JSON — 키 바인딩 map
- options JSON — 게임별 자유 옵션
- updated_at utc_datetime
- unique (user_id, game_type)
```

### 페이지

- `/settings/games/:game_type` — LiveView, 옵션 폼.
- `/settings/games` — 게임 목록 + "옵션" 링크.
- 각 게임 페이지 (`/play/:type`, `/game/:type/:id`)에 ⚙️ 버튼 → 옵션 모달.

### 게스트 처리

- localStorage 사용 (key: `happy_trizn_game_settings_<game_type>`).
- 등록자 가입 시 localStorage → DB 마이그.

---

## Tetris (Jstris 모방)

가장 디테일하게 작성. 다른 게임 spec 의 reference.

### 게임 plan logic

- 10×22 board (상단 2행 hidden spawn buffer)
- **7-bag random** (현재 구현됨)
- **SRS (Super Rotation System)** — wall kick / floor kick 5-test table (현재 basic rotation 만)
- **180도 회전** (별도 키, SRS 와 별개)
- **Hold** — 한 piece 보관 + swap. 라운드당 1회 (lock 후 다음 piece spawn 전까지).
- **Lock delay** — piece 가 landed 상태에서 일정 시간 (default 500ms) 안에 이동/회전 가능.
- **Soft drop** — 속도 옵션 (느림/중간/빠름/매우빠름/즉시) per user.
- **Hard drop** — 즉시 lock + score +(2 × distance).
- **Line clear** — 표준 점수 (single 100/double 300/triple 500/tetris 800 × level).
- **Combo** — 연속 line clear, combo bonus (현재 미구현).
- **B2B (Back-to-Back)** — Tetris/T-spin 연속 시 ×1.5 보너스.
- **T-spin** — T piece 회전 시 3-corner 검증, T-spin single/double/triple 점수.
- **Garbage** — Jstris 매핑 (single 0/double 1/triple 2/tetris 4). T-spin/B2B 시 추가.
- **Garbage queue** — 받을 때 hole column 같으면 합쳐서 한 hole 로.
- **Top out** — spawn 못 함 = 게임 오버.

### 사용자 게임 옵션

#### 키 바인딩 (per user, 모두 변경 가능)

| 액션 | default | 추가 옵션 예 |
|---|---|---|
| 왼쪽 이동 | ← | a, j |
| 오른쪽 이동 | → | d, l |
| 소프트 드랍 | ↓ | s, k |
| 하드 드랍 | Space | w |
| 왼쪽 회전 | Ctrl, Z | x |
| 오른쪽 회전 | ↑ | X, z |
| 180 회전 | A | c |
| 홀드 | Shift, C | a, e |
| 일시정지 | Esc | p |

`key_bindings` JSON 예:
```json
{
  "move_left": ["ArrowLeft", "j"],
  "move_right": ["ArrowRight", "l"],
  "soft_drop": ["ArrowDown", "k"],
  "hard_drop": [" "],
  "rotate_cw": ["ArrowUp", "z"],
  "rotate_ccw": ["x"],
  "rotate_180": ["c"],
  "hold": ["a", "Shift"],
  "pause": ["Escape"]
}
```

#### 게임 설정 (`options` JSON)

- **DAS** (Delayed Auto Shift) — 좌우 키 누른 후 자동 반복 시작까지 ms (default 133, 범위 0~500)
- **ARR** (Auto Repeat Rate) — DAS 후 한 칸 이동마다 ms (default 10, 범위 0~100, 0=즉시)
- **소프트 드랍 속도** — `:slow` `:medium` `:fast` `:very_fast` `:instant`
- **그리드** — `:none` `:standard` `:partial` `:vertical` `:full`
- **고스트** — bool (default true)
- **블록 스킨** — `:flat_solid` `:translucent` `:default_jstris` `:srs_classic` 등
- **블록 색** — flat_solid 일 때 hex (default `#5c5c5c`)
- **사운드 효과음 크기** — 0~100% (default 16)
- **효과음 옵션** (각 bool):
  - 게임 시작 알림음
  - 블록 회전 효과음
  - 피네스 오류 경고음
  - 플레이어 접속 알림음
  - 메시지 알림음
- **음성 해설** — string (해설자 이름) 또는 nil
- **표시할 통계** (multi-select):
  - 라운드 시간 / 점수 / 줄 / 공격 / 받음 / 피네스 / PPS / KPP / APM / 블록 / VS / Wasted / Hold
- **모드** — `:realtime` `:replay` 등

### Stats 계산

- **PPS** (Pieces Per Second) — 분당 piece / 60.
- **KPP** (Keys Per Piece) — input 수 / piece 수.
- **APM** (Attacks Per Minute) — garbage send / minute.
- **Finesse** — piece 한 개당 최소 input 수 위반 카운트.
- **VS** — 상대보다 우위 (점수/공격/받음 종합).
- **Wasted** — pending garbage 받았는데 line clear 로 cancel 못한 양.
- **Hold count** — hold 사용 횟수.

라운드 끝 시 `match_results` 에 저장 + Mongo `game_events` 에 매 piece event.

---

## Bomberman

### 게임 logic

- 격자 13×11 (전형적 Bomberman 사이즈)
- 4명 동시
- 벽 (파괴 불가) + 블록 (파괴 가능, 아이템 드롭 가능성 있음)
- 폭탄 — 길이 / 개수 강화 아이템
- 아이템: 화염 강화, 폭탄 +1, 스피드, 발차기, 펀치
- 60fps tick (서버 권위)
- 마지막 1명 winner

### 옵션

- 키 바인딩: 상하좌우, 폭탄 설치, 발차기, 펀치
- 스피드 / 폭탄 효과음
- 그리드 색 / 캐릭터 스킨

---

## Skribbl

### 게임 logic

- 5+ 인 (max 8)
- 라운드: 한 사람이 그리는 사람 (drawer), 단어 받음, 캔버스에 그림.
- 다른 사람들 채팅으로 단어 맞추기. 정답 시 점수.
- 시간 제한 (default 80초). 시간 끝나면 다음 차례.
- 단어 사전 (한국어/영어 선택).
- 그림 broadcast 매 stroke (Phoenix Channel 으로 60fps).

### 옵션

- 캔버스 도구: 펜 / 지우개 / 색상 (palette)
- 채팅 알림음 on/off
- 단어 사전 (한/영)
- 라운드 시간 (60/80/100/120)

---

## Snake.io

### 게임 logic

- 자유 입퇴장 (캐주얼)
- 무한 맵 (또는 큰 격자 100×100)
- 먹이 random spawn → 길이 +1
- 다른 뱀 / 자기 몸 부딪히면 죽음 → 길이 dot 흩뿌림
- 점수 = 길이
- 60fps tick

### 옵션

- 키 바인딩 (상하좌우)
- 색 (랜덤 vs 고정)
- 미니맵 표시

---

## 2048

### 게임 logic (현재 구현됨)

- 4×4 grid
- swipe (방향키) → 같은 숫자 합쳐서 +
- win 2048
- 변화 없는 방향 무효

### 옵션 (추가)

- 키 바인딩 (방향키 외 wasd, hjkl)
- board 사이즈 (4×4 / 5×5 / 6×6)
- 다크/라이트 테마

---

## Minesweeper

### 게임 logic (현재 구현됨)

- 10×10 / 12 mines
- first-click safe zone
- BFS flood reveal
- flag toggle
- win/lose

### 옵션 (추가)

- 난이도: easy (9×9, 10 mines) / medium (16×16, 40) / hard (16×30, 99) / custom
- 시간 표시
- 좌클릭 reveal vs 우클릭 flag (또는 둘 다 한 버튼)

---

## Pac-Man

### 게임 logic (Sprint 3b-3 풀 구현)

- 표준 Pac-Man maze (~28×31)
- 4 ghost (Blinky/Pinky/Inky/Clyde) AI
- 도트 / 파워 펠릿 / 과일
- ghost frightened 모드
- 점수 / 라이프 3 / 레벨

### 옵션

- 키 바인딩 (상하좌우 + wasd)
- 사운드 (먹기/death/intro)

---

## DB 스키마

### 새 테이블

```
user_game_settings
- id binary_id PK
- user_id FK users (cascade delete)
- game_type string(32)
- key_bindings JSON
- options JSON
- updated_at utc_datetime
- unique (user_id, game_type)

match_results (이미 있음, 확장)
- id binary_id PK
- game_type string(32)
- room_id binary_id (멀티만)
- winner_id binary_id FK users (nullable, 싱글은 null)
- duration_ms integer
- stats JSON — 게임별 (Tetris: PPS/APM/lines/score; 2048: max tile/score)
- finished_at utc_datetime
- inserted_at utc_datetime

personal_records (싱글 게임용)
- id binary_id PK
- user_id FK users
- game_type string(32)
- score integer
- duration_ms integer
- metadata JSON — 게임별 (Tetris: lines/level; Minesweeper: difficulty/time)
- achieved_at utc_datetime
- index (user_id, game_type, achieved_at desc)
```

---

## 구현 순서

| Sprint | 게임 / 기능 |
|---|---|
| 3b-3 | **Tetris 본격** — SRS / wall kick / hold / 180 회전 / lock delay / combo / B2B / T-spin |
| 3b-4 | **사용자 옵션 시스템** — `user_game_settings` schema + `/settings/games/:type` LiveView + Tetris 옵션 (key binding + DAS/ARR/grid/ghost/skin/sound) |
| 3b-5 | **JS 클라이언트 canvas** — Tetris board canvas render (블록 스킨 + 그리드 + 고스트) + DAS/ARR client-side timing |
| 3b-6 | **통계** — 매 라운드 stats 계산 + match_results 저장 + LiveView 표시 |
| 3b-7 | **사운드** — 효과음 + 음성 해설 |
| 3c | Bomberman 풀 구현 |
| 3d | Skribbl 풀 구현 |
| 3e | Snake.io 풀 구현 |
| 3f | Pac-Man 풀 구현 |
| 3g | 2048 / Minesweeper 옵션 보강 |
| 4 | DM Channel + match_results / personal_records UI + Broadway Mongo 큐 |

---

## 우선순위

1. **Tetris 본격** (Jstris 수준) — 사용자 가장 좋아함. Hold / SRS / 좌우 회전 / 180 / 키 바인딩 customizable.
2. **사용자 옵션 시스템** — 모든 게임 공통 인프라.
3. JS canvas (DAS/ARR client-side).
4. 다른 게임 풀 구현.
