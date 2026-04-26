# Games Spec — 사내 게임 허브 (Happy Trizn)

각 멀티/싱글 게임의 본격 spec + 진행 트래킹. **각 게임 PR 시 참조**.

## 목차

- [공통 — 사용자 게임 옵션](#공통--사용자-게임-옵션)
- [Tetris ✅](#tetris--구현-완료)
- [캐치마인드 ✅ (구 Skribbl)](#캐치마인드--구현-완료)
- [Bomberman ⏳](#bomberman--미구현)
- [Snake.io ⏳](#snakeio--미구현)
- [Pac-Man ⏳](#pac-man--미구현)
- [2048 + Minesweeper ⏳ (싱글, 옵션 보강 대기)](#2048--minesweeper--싱글-옵션-보강)
- [DB 스키마](#db-스키마)
- [구현 진행 상황](#구현-진행-상황)

---

## 공통 — 사용자 게임 옵션 ✅

각 사용자가 게임마다 자기 옵션 저장. 게스트 = default (저장 안 함).

### Schema (구현됨)

```
user_game_settings
- id binary_id PK
- user_id FK users (cascade delete)
- game_type string(32)  — "tetris", "skribbl", ...
- key_bindings JSON
- options JSON
- updated_at utc_datetime
- unique (user_id, game_type)
```

### 페이지 (구현됨)

- `/settings/games` — 게임 목록 + 옵션 링크
- `/settings/games/:game_type` — 게임별 폼 (Tetris 전용 + 제너릭 fallback)
- **각 게임 화면 ⚙️ 옵션 → 인라인 모달** (페이지 안 옮김, 게임 유지)

### 글로벌 인프라 (구현됨)

- 🏠 **글로벌 top nav** (root layout): `Happy Trizn` 브랜드 + `/` + 페이지 타이틀
- 🏆 **개인 기록 페이지** (`/history`) + **리더보드** (`/history/leaderboard/:type`)
- **인라인 옵션 모달** — 게임 안에서 즉시 변경, 저장 후 즉시 반영 (data-* 갱신 → JS hook 재파싱)
- **ChatReset hook 일반화** — chat:reset_input 이벤트 받아 form 안 모든 input 비움

---

## Tetris ✅ 구현 완료

(Jstris 수준)

### 게임 로직 (모두 구현)

- 10×22 board (상단 2행 hidden spawn buffer)
- **7-bag random** ✅
- **SRS** + wall kick (JLSTZ 5-test + I 5-test + 180 kick) ✅
- **CW / CCW / 180 회전** (별도 액션) ✅
- **Hold piece** — 라운드당 1회, swap, top_out 검사 ✅
- **Lock delay** — 500ms grace, 회전/이동 시 reset (max 15회), tick 강제 lock ✅
- **Soft / Hard drop** — score +1 / +2×distance ✅
- **Line clear**: single 100 / double 300 / triple 500 / tetris 800 × level ✅
- **Combo** + **B2B** (×1.5 점수 + garbage +1) ✅
- **T-spin detection**: 4-corner test + front corners → tspin / tspin_mini ✅
- **Garbage table**: cleared - 1, tetris 4, t-spin double 4, triple 6, b2b/combo bonus ✅
- **Garbage cancel** (jstris): line clear 시 min(send, pending) 차감 ✅
- **Garbage spoiler bar**: board 좌측 빨간 bar — pending 만큼 미리 경고 ✅
- **Garbage overflow fix**: lines 캡 + visible_height 도달 시 무조건 top_out ✅
- **Top out 시 board 에 가비지 적용** (시각적 가득) ✅
- **Top out** → 상대 자동 winner ✅

### 멀티 / 라운드 흐름 (구현)

- :waiting (1명) → 🎯 **솔로 연습 (`:practice`)** ✅
- 2번째 player join → 양쪽 reset → **:countdown 3-2-1** → :playing ✅
- 한 명 leave → 남은 사람 **자동 :practice** (winner X, 게임 영향 X) ✅
- 끝나도 GenServer 유지 → **🔄 다시 하기** 가능 ✅
- 모든 player leave → GenServer :stop → 방 자동 close ✅
- **Restart action** + winners_history 보존 ✅

### 사용자 게임 옵션 (구현)

- 키 바인딩 9개 (move_left/right/soft_drop/hard_drop/rotate_cw/ccw/180/hold/pause). 사용자 변경 가능 ✅
- DAS / ARR (ms) ✅
- 소프트 드랍 속도 ✅
- 그리드 (none/standard/partial/vertical/full) ✅
- 고스트 (옵션) — piece type별 색 + 40% opacity + 두꺼운 border ✅
- 사운드 (마스터 볼륨 + 8개 효과음 on/off) ✅

### 사운드 (WebAudio 합성) ✅

- rotate / lock / line_clear / tetris / b2b / garbage / top_out / countdown
- 외부 mp3 없이 oscillator + envelope 절차 합성
- 첫 user input 후 AudioContext unlock (autoplay policy)

### 통계 ✅

- pieces_placed / keys_pressed / garbage_sent / received / wasted / hold_count
- PPS / KPP / APM / duration_ms (public_stats/1)
- match_results 자동 저장 (game_over 시) + dedupe
- 매 라운드 PersonalRecords.apply_stats 호출 → max_score/lines + max_pps/apm/kpp

### UI (구현)

- **Hold (좌) | Board (중) | Nexts ×5 (우)** 3-column 레이아웃 ✅
- 다음 5 piece 큐 (`Tetris.upcoming/2`) ✅
- 콤보 / B2B 배지 ✅
- 게임 종료 popup overlay (큰 이모지 + 누적 우승 + 다시 하기) ✅
- Lock delay 표시 ("잠금 NNNms") ✅

### JS 입력 모듈 (`assets/js/hooks/tetris_input.js`) ✅

- e.code 기반 매칭 (한/영 IME 우회)
- 단일 문자 case-insensitive
- DAS / ARR auto-repeat (left/right/soft_drop)
- 같은 action 다중 키 OR (ArrowLeft + j)
- input field 안에서는 skip (모달 입력 가능)

---

## 캐치마인드 ✅ 구현 완료

(구 Skribbl, 이름 변경)

### 게임 로직 (구현)

- 2~8인 멀티 ✅
- **5 라운드** (player 수 무관) ✅
- Drawer round-robin (적게 그린 사람부터) ✅
- 단어 선택 30초 → 그리기 80초 → 라운드 종료 5초 → 다음 ✅
- 모든 사람 맞추거나 timer 0 → round_end ✅
- **150+ 한국어 단어** (일상 / 인기 게임 / 유명 만화애니 / 메인스트림 개발 / 일상 활동) ✅

### 점수 (구현)

- guesser: `50 + 100 × (남은시간/80초)` → 50~150점 ✅
- drawer bonus: 맞춘 사람당 +50 ✅

### 캔버스 (구현)

- HTML `<canvas>` + JS pointer events (mouse + touch) ✅
- 7색 + 4 크기 + 지우개 (event delegation 으로 LiveView re-render 안전) ✅
- Stroke 매번 server push + 로컬 즉시 반영 ✅
- 늦게 join 시 **strokes_replay** ✅
- Stroke sanitization (color hex / size 1~30 / coords 0~2000 clamp) ✅

### Round / Game 종료 popup ✅

- round_end 모달: 정답 공개 + 맞춘 사람 순위 + 다음 라운드 카운트
- game_over 모달: 우승자 + top 8 점수 + 다시 하기

### 채팅 ✅

- 정답 누설 방지 (drawer 채팅 차단)
- 이미 맞춘 사람 추가 chat 차단
- 입력창 자동 reset (push_event chat:reset_input)

### 옵션 ✅ (제너릭 폼)

- chat_sound (bool)
- dictionary (한/영 — 현재 한국어만)
- round_seconds (60/80/100/120)
- default_pen_color

---

## Bomberman ⏳ 미구현

### 게임 로직 (계획)

- 격자 13×11
- 4명 동시
- 벽 (파괴 불가) + 블록 (파괴 가능, 아이템 드롭)
- 폭탄 — 길이 / 개수 강화
- 아이템: 화염 강화, 폭탄 +1, 스피드, 발차기, 펀치
- 60fps tick (서버 권위)
- 마지막 1명 winner

### 옵션 (defaults 만 구현, 게임 로직 미구현)

- 키: 상하좌우, 폭탄 설치, 발차기, 펀치
- 스피드 / 폭탄 효과음
- 그리드 색 / 캐릭터 스킨

---

## Snake.io ⏳ 미구현

### 게임 로직 (계획)

- 자유 입퇴장
- 큰 격자 100×100
- 먹이 random spawn → 길이 +1
- 부딪히면 죽음 → 길이 dot 흩뿌림
- 60fps tick

### 옵션 (defaults 만 구현)

- 키 (상하좌우)
- 색
- 미니맵

---

## Pac-Man ⏳ 미구현

### 게임 로직 (계획)

- 표준 maze 28×31
- 4 ghost AI (Blinky/Pinky/Inky/Clyde)
- 도트 / 파워 펠릿 / 과일
- ghost frightened 모드
- 점수 + 라이프 3 + 레벨

### 옵션 (defaults 만 구현)

- 키 (방향키 + WASD)
- 사운드 (먹기/death/intro)

---

## 2048 + Minesweeper ⏳ 싱글, 옵션 보강

### 2048 (게임 동작 구현됨, 옵션 미보강)

- 4×4 grid + swipe + 합치기 + win 2048

#### 옵션 (defaults 있음)

- 키 (방향키 + WASD + HJKL)
- board 사이즈 (4/5/6) — **로직 보강 필요**
- 다크/라이트 테마

### Minesweeper (게임 동작 구현됨, 옵션 미보강)

- 10×10 / 12 mines / first-click safe / BFS reveal / flag

#### 옵션 (defaults 있음)

- 난이도 (easy/medium/hard/custom) — **로직 보강 필요**
- 시간 표시
- 좌클 reveal vs 우클 flag

---

## DB 스키마

### 구현됨 ✅

```
user_game_settings  ✅
- id, user_id, game_type, key_bindings JSON, options JSON, updated_at
- unique (user_id, game_type)

match_results  ✅
- id, game_type, room_id, winner_id, duration_ms, stats JSON, finished_at, inserted_at
- index (game_type, winner_id, finished_at, room_id)

personal_records  ✅
- id, user_id, game_type, max_score, max_lines, total_wins, metadata JSON, achieved_at
- unique (user_id, game_type), index (game_type)
```

### 미구현 (향후)

```
notifications (?)  — 친구 요청 / 게임 초대 알림
direct_messages (?) — DM
```

---

## 구현 진행 상황

| Sprint | 내용 | 상태 |
|---|---|---|
| **3b-3** | Tetris 본격 (SRS / wall kick / hold / 180 / combo / B2B / T-spin / 7-bag / garbage queue / top out) | ✅ |
| **3b-3** | 사용자 옵션 시스템 1차 (`user_game_settings` schema + LiveView + Tetris key binding 폼) | ✅ |
| **3b-3** | JS DAS/ARR hook (TetrisInput) | ✅ |
| **3b-4** | Lock delay (500ms, max 15 resets) | ✅ |
| **3b-4** | 통계 (PPS/KPP/APM/pieces/garbage/wasted/hold_count) | ✅ |
| **3b-4** | match_results auto save (game_over) + dedupe | ✅ |
| **3b-4** | Ghost piece + grid 옵션 + 모든 게임 settings defaults | ✅ |
| **3b-4** | Lobby ⚙️ 옵션 링크 + 글로벌 페이지 link | ✅ |
| **3b-4** | 솔로 연습 + 3-2-1 카운트다운 + 다시 하기 | ✅ |
| **3b-5** | 사운드 시스템 (8 효과음 WebAudio) + 옵션 마스터 볼륨 + 각 on/off | ✅ |
| **3b-5** | 매치 히스토리 (`/history`) + 리더보드 (`/history/leaderboard/:game_type`) | ✅ |
| **3b-5** | 개인 기록 (`personal_records` schema + apply_stats max merge + leaderboard) | ✅ |
| **3b-5** | GenServer freeze fix (player_state payload 직접 사용 + countdown throttle) | ✅ |
| **3b-5** | top_out 시 board 에 가비지 적용 (시각적 패배) | ✅ |
| **3b-5** | 가비지 cancel 로직 + 빨간 spoiler bar | ✅ |
| **3b-5** | Hold/Board/Nexts 3-column + 다음 5 piece 큐 | ✅ |
| **3d** | 캐치마인드 풀 구현 — state machine / canvas / chat / 점수 / 5 라운드 / round_end & game_over popup | ✅ |
| **3d** | Tetris leave :practice 자동 전환 (1명 남으면 게임 영향 X) | ✅ |
| **3d** | 글로벌 top nav (Happy Trizn 브랜드 + 페이지 타이틀) | ✅ |
| **3d** | 게임명 캐치마인드 (lobby badge 친화 이름) | ✅ |
| **3e** | Bomberman 풀 구현 | ⏳ |
| **3f** | Snake.io 풀 구현 | ⏳ |
| **3g** | Pac-Man 풀 구현 (싱글) | ⏳ |
| **3h** | 2048 / Minesweeper 옵션 로직 보강 (board 사이즈 / 난이도) | ⏳ |
| **3i** | Finesse 분석 (현재 stub 0) | ⏳ |
| **3j** | JS Tetris canvas (블록 스킨 / DAS-ARR client-side timing — 현재 server timing) | ⏳ |
| **3k** | 모바일 반응형 (canvas / 옵션 모달 / 채팅) | ⏳ |
| **4** | DM Channel + 알림 시스템 + Broadway Mongo 큐 (game_events) | ⏳ |

---

## 우선순위 (남은 작업)

1. **Bomberman 풀 구현** (3e) — 4인 동시, 60fps tick, 폭탄 chain reaction. 회식 분위기 좋음.
2. **Snake.io 풀 구현** (3f) — 자유 입퇴장 + 큰 격자.
3. **Pac-Man 풀 구현** (3g) — 싱글 + ghost AI.
4. **2048 / Minesweeper 옵션 로직 보강** (3h) — 보드 사이즈 / 난이도 적용.
5. **모바일 반응형** (3k) — 캔버스 / 모달 / 채팅 layout.
6. **JS Tetris canvas + skin** (3j) — 더 화려한 렌더 (현재 LiveView grid).
7. **Finesse 분석** (3i) — Tetris finesse_violations 카운트.
8. **DM + 알림** (4) — 친구 1:1 채팅, 게임 초대.

## 테스트 현황

- **430 tests, 0 failures** (Sprint 3d 기준).
- ExUnit 단위/통합 + LiveView 테스트.
- E2E (Playwright) 미구현 (TEST_PLAN.md 참조).
