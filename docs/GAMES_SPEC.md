# Games Spec — 사내 게임 허브 (Happy Trizn)

각 멀티/싱글 게임의 본격 spec + 진행 트래킹. **각 게임 PR 시 참조**.

## 목차

- [공통 — 사용자 게임 옵션](#공통--사용자-게임-옵션)
- [Tetris ✅](#tetris--구현-완료)
- [캐치마인드 ✅ (구 Skribbl)](#캐치마인드--구현-완료)
- [Bomberman ✅](#bomberman--구현-완료)
- [Snake.io ✅](#snakeio--구현-완료)
- [Pac-Man ✅](#pac-man--구현-완료)
- [2048 + Minesweeper ✅ (싱글, 옵션 보강 완료)](#2048--minesweeper--옵션-로직-보강-완료-sprint-3h)
- **[Trizmon ⏳ (Sprint 5c — 장기 flagship, 별도 spec)](TRIZMON_SPEC.md)** — 자체 IP 몬스터 RPG. 모험 / PvE / PvP 3 모드. 18 타입 / 진화 / 도감 / AI 생성 이미지
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
- (Sprint 4i) 셀 inset bevel — `.tetris-filled` (메인 24px) / `.tetris-filled-mini` (opp 12px) box-shadow → 같은 색 인접 블록끼리 셀 윤곽 분리. 빈 셀 무영향.

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

## Bomberman ✅ 구현 완료

### 게임 로직 (구현)

- 13×13 격자 (체스판 wall + 70% destructible block) ✅
- 2~4명 동시. spawn corner = (1,1) (1,11) (9,1) (9,11) ✅
- 50ms tick (20fps) ✅
- 폭탄 fuse 3000ms → ray-cast 폭발 + chain reaction ✅
- 4 아이템 종류 (block 파괴 시 20% drop): bomb_up / range_up / speed_up / kick ✅
- 마지막 1명 alive → :over + winner_id ✅
- player_id = session.id (multi-tab 테스트 가능) ✅

### UI (구현)

- 셀 48px (`w-12 h-12 text-2xl`), 보드 외곽 gradient ring + shadow ✅
- terrain gradient (벽 slate / 블록 amber / empty emerald-tinted) ✅
- 폭탄 fuse 별 animate-bounce/animate-pulse + glow drop-shadow ✅
- 아이템 4종 컬러별 glow + bounce (💥🔥⚡🦵) ✅
- 플레이어 4 아바타 (🤺🦸🥷🧙) + 4색 ring (red/blue/emerald/yellow), index 안정 매핑 ✅
- 게임방 ephemeral chat (Skribbl 제외, 방 닫히면 휘발) ✅

### Stuck modal 회피 (Sprint 3e+)

- :over 후 1명 leave → handle_player_leave 가 자동 :waiting 리셋 (grid/bombs/items/winner_id 초기화 + spawn corner 재배치).
- :over + 인원 부족 시 "다시 하기" → reset_to_waiting (modal 사라지게).
- Skribbl 도 동일 패턴 적용. Tetris 는 기존 :practice 자동 전환으로 안전.

### UX 픽스 (Sprint 4i)

- **폭발 자동 클리어**: tick/1 에서 bombs/explosions 활성 시 `:state_changed` PubSub broadcast → LiveView catch-all `refresh_state` 트리거. 사용자 입력 없어도 폭발 ttl 끝나면 화면 자동 갱신. 비활성 시 broadcast 안 함 (50ms tick spam 방지).
- **폭탄 + 플레이어 z-order**: `bomberman_cell_content` 에서 같은 셀 player + bomb 동시 처리 → cell wrapper `relative` + 두 visual 을 absolute 로 겹쳐 player 가 z-10 으로 위. 자기 위치에 폭탄 놓아도 캐릭터 안 사라짐.
- **채팅 height**: aside 가 `flex flex-col gap-3 min-h-0` 로 변경, `game_room_chat` 에 `flex-1 min-h-0` 패스 → 채팅이 게임 grid 높이 만큼 늘어남 (기존 280px 고정 → 동적).

### 옵션

- 키: 상하좌우, 폭탄 설치 (defaults), 발차기/펀치 (defaults; 로직 미구현)
- 스피드 / 폭탄 효과음 (defaults; 사운드 모듈 미구현)
- 그리드 색 / 캐릭터 스킨 (defaults; 미구현)

### JS 입력 (`assets/js/hooks/bomberman_input.js`) ✅

- e.code 기반 매칭, isFormTarget skip, OS auto-repeat.

---

## Snake.io ✅ 구현 완료

### 게임 로직 (구현)

- **200×200 월드 격자** (io 게임 느낌, 큰 맵), 자유 입퇴장, 항상 :playing (캐주얼)
- 50ms tick (20fps)
- food 항상 max(60, players × 8) 개 유지
- food 먹으면 length +1 (grow 카운터로 다음 trim skip)
- 충돌 (벽 / 자기 몸 / 타 snake 몸) → 사망 + body 절반 food drop
- 머리 vs 머리 → 양쪽 사망
- tail follow 허용 (tail 다음 tick 에 빠지므로 self-collision 시 tail 제외)
- 사망 후 60 tick (3초) 자동 부활 (length 3 + 랜덤 위치)
- 180° 반대 방향 입력 무시
- best_length / kills 누적 — 리더보드.
- `game_over?` 항상 `:no`.

### UI — 카메라 추적 viewport

- 월드 200×200 → 클라가 본인 head 중심 **40×40 셀 viewport** (640×640 px) 만 그림.
- 셀 16px (이전 6px → 2.7배 키움) — 조작 편함.
- viewport 가 월드 가장자리 도달하면 clamp + 외곽 dark zone 표시.
- 색 16종 자동 unique 분배 + 본인 head 흰색 ring.
- 사망 snake 25% 알파.
- 리더보드 best_length 정렬 + 본인 굵은 표시.
- HUD: 좌상단 좌표 (`(r, c) / 200`).
- 게임방 ephemeral chat (Tetris/Bomberman 과 동일).
- (Sprint 4i) 채팅 height — aside `flex flex-col gap-3 min-h-0`, `game_room_chat` 에 `flex-1 min-h-0` 패스 → 캔버스 (640px) 만큼 채팅 늘어남.

### Tick broadcast (구현)

- `Snake.tick` 마다 `[{:snake_state, %{players, food, tick_no}}]` PubSub.
- LiveView handle_info 가 payload 로 game_state 직접 갱신 (GenServer.call 안 함 — Tetris freeze 패턴 회피).
- canvas 라 DOM diff 부담 X.

### JS hook (구현)

- `snake_input.js` — 4 방향 + WASD, 25ms throttle, isFormTarget skip.
- `snake_canvas.js` — mounted/updated 마다 dataset 파싱 + 본인 head 중심 카메라 + viewport 그리기.

---

## Pac-Man ✅ 구현 완료

### 게임 로직 (구현)

- 표준 28×31 maze (벽 / dot / power pellet / ghost door / tunnel wrap row14) ✅
- Pac-Man + 4 ghost — 100ms tick (10fps 클래식 느낌) ✅
- ghost AI 4종 (Blinky/Pinky/Inky/Clyde) — chase target 차별화 ✅
  - Blinky: Pac-Man 직진 추격.
  - Pinky: Pac-Man 4칸 앞.
  - Inky: Pac-Man 2칸 앞 + Blinky 거리.
  - Clyde: 8칸 이상 → chase, 가까우면 scatter.
- :scatter ↔ :chase 모드 자동 전환 (각 7s / 20s) ✅
- power pellet → :frightened 8s — ghost 도망, 잡히면 +200/400/800/1600 ✅
- :eaten ghost 자기 spawn 위치로 복귀 후 재진입 ✅
- Pac-Man 잡힘 → :dying (애니메이션) → 라이프 -1 → respawn or :over ✅
- 모든 dot/pellet 먹으면 :won → 다음 level (score/lives 누적) ✅

### UI (구현)

- HTML canvas 560×620 (셀 20px) ✅
- 벽 진한 파랑 + inner stroke 라이트 파랑.
- dot 작은 점, pellet 큰 점 + blink 애니.
- Pac-Man 노란 원 + 입 열고닫음 (tick 패리티), dir 별 회전.
- ghost 4 색 (red/pink/cyan/orange) + 톱니 아래쪽 + dir 별 눈동자.
- frightened 시 짙은 파랑 + 끝나기 직전 흰색 깜빡 + 작은 입 무늬.
- :eaten 시 본체 X, 눈만.
- HUD: 점수 / 라이프 / 레벨 / GAME OVER 배지.

### 인프라 (구현)

- 싱글 게임용 GameLive — `connected?` + `:timer.send_interval` 으로 LiveView 안에서 직접 tick 발행 (멀티는 GameSession 이 처리).
- key_to_action: 방향키 + WASD → `set_dir`.
- GameKeyCapture hook 으로 page-scroll 회피.

### JS hook

- `pacman_canvas.js` — mounted/updated 마다 payload 재그림.
- 새 hook 등록 (`assets/js/app.js`).

---

## 2048 + Minesweeper ✅ 옵션 로직 보강 완료 (Sprint 3h)

> Slug ↔ settings_key 정규화: `UserGameSettings.normalize_game_type/1` 가
> slug `"2048"` → DB game_type `"games_2048"` 자동 변환. `defaults/get_for/upsert/reset`
> 모두 alias 따라가서 `/settings/games/2048` 폼 + 저장이 정상 동작.



### 2048 ✅

- N×N grid (4 / 5 / 6) + swipe + 합치기 + win 2048
- `init/1` 가 `%{"board_size" => N}` 받아 동적 grid 생성. `state.size` 보유.
- restart 시 size 유지.

#### 옵션

- 키 (방향키 + WASD + HJKL)
- **board 사이즈 (4 / 5 / 6)** ✅ — 그리드 inline `grid-template-columns: repeat(N, ...)` 렌더
- 다크/라이트 테마

### Minesweeper ✅

- N×M grid + first-click safe + BFS reveal + flag
- `init/1` 이 `%{"difficulty" => preset}` 받아 dims 결정
- restart 시 dims/difficulty 유지

#### 난이도 프리셋 ✅

| 프리셋 | rows × cols | mines |
|---|---|---|
| `easy` | 9×9 | 10 |
| `medium` | 16×16 | 40 |
| `hard` | 16×30 | 99 |
| `custom` | rows ∈ [5..30], cols ∈ [5..40] | 1 ~ rows×cols-9 자동 캡 |

- `init(%{})` (테스트/구버전) → 10×10/12 fallback
- 알 수 없는 difficulty → 같은 fallback

#### 옵션

- 키 (좌클 reveal · 우클 / 'F' flag)
- **난이도 (easy/medium/hard/custom)** ✅
- custom 시 `custom_rows` / `custom_cols` / `custom_mines` 필드
- 시간 표시

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
| **3e** | Bomberman 풀 구현 + 셀/이모티콘 폴리시 + 게임방 채팅 | ✅ |
| **3e+** | 게임 종료 후 1명 남으면 :waiting 자동 리셋 (Bomberman/Skribbl stuck modal 회피) | ✅ |
| **3f** | Snake.io 풀 구현 (100×100 격자 + 캔버스 + 자동 부활) | ✅ |
| **3g** | Pac-Man 풀 구현 (28×31 maze + ghost AI 4종 + frightened) | ✅ |
| **3l** | 마이페이지 (닉네임 수정 + 프로필 사진 + Bomberman 둥근 아바타) | ✅ |
| **3h** | 2048 / Minesweeper 옵션 로직 보강 (board 사이즈 / 난이도) | ✅ |
| **3h** | 2048 키보드 입력 (화살표 / WASD / HJKL) | ✅ |
| **3h** | Settings slug ↔ game_type alias 정규화 (`2048` → `games_2048`) | ✅ |
| **3i** | Tetris Finesse 분석 — spawn → lock 사이 left/right/rotate* 입력 수 vs optimal, violations 카운터 + UI 뱃지 | ✅ |
| **3j** | JS Tetris canvas (HTML5 Canvas opt-in renderer) + 4 skin (default_jstris/vivid/monochrome/neon) | ✅ |
| **3k** | 모바일 반응형 (LiveView padding p-3 sm:p-6 / DM 단일창 toggle / 게임판 cell 크기 sm: 분기) | ✅ |
| **3l** | Tetris jstris 식 multi-player UI (mini board grid + 채팅 우측) + N-player (max 8) + 가비지 random alive 타겟팅 + ranking modal (🥇🥈🥉) + live HUD (PPS/APM/VS/KPP) | ✅ |
| **3l-6/7** | Bomberman + Skribbl 도 ranking modal 통일 (game_over.ranking + 본인 row primary highlight) | ✅ |
| **3m** | 스도쿠 (싱글) — 9×9 valid 자동 생성 (base + symmetry transforms) + 난이도 3종 + 충돌 감지 highlight | ✅ |
| **4a/b/c** | DM 1:1 + 친구 게임 초대 + 채팅창 height 고정 | ✅ |
| **4d** | Broadway Mongo 큐 (game_events) — Producer GenStage + batcher 100/1s, Mongo 다운 시 silent skip | ✅ |
| **4f** | 지뢰찾기 (Minesweeper rename) — phx-value string→int 강제 + cursor + 화살표/Space/Enter/F + MinesweeperCell hook 우클릭 | ✅ |
| **4g** | Presence (Phoenix.Presence) — 친구 접속중 🟢 dot. fetch_live_user hook 자동 track | ✅ |
| **4i** | 4 테마 시스템 (Light+ / Dark+ / Night Owl / Hacker Terminal) + Bomberman 폭발 자동 클리어/z-order + Snake.io 채팅 fill + Tetris 셀 bevel + 모달 브릿지 | ✅ |
| **4h** | Lobby/DM/Nav UX 풀세트 (헤더 통합 / 닉네임 dropdown / 페이지네이션 / 친구 섹션 시각 구분) | ✅ |
| **4e** | 사내 서버 배포 + HTTPS (Caddy/nginx) | ⏳ |

---

## 우선순위 (남은 작업)

1. **사내 서버 배포 + HTTPS** (4e) — Caddy 또는 nginx + Let's Encrypt.
2. **E2E** — Playwright (Tetris 1v1, Skribbl, DM 알림, 모바일 viewport).
3. **가비지 동시 다중 타겟** — Tetris N-player 분산 ATK distributor.
4. **모바일 게임 컨트롤** — 가상 D-pad / tap & long-press.
5. **Spectator 모드** — 진행 중 게임 관전.

## 테스트 현황

- **658 tests, 0 failures** (Sprint 3m + 4f + 4g + 4h 머지 후 기준).
- ExUnit 단위/통합 + LiveView 테스트.
- 새로 추가: Bomberman + Skribbl `:over → leave/restart → :waiting 리셋`, Snake.io 19 tests, 게임방 채팅 broadcast.
- E2E (Playwright) 미구현 ([TEST_PLAN.md](TEST_PLAN.md) 참조).
