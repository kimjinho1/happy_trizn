# Test Plan

Branch tracking. 최근 갱신: Sprint 3m 스도쿠 + Sprint 4f 지뢰찾기 fix + Sprint 4g Presence (친구 접속중) + Sprint 4h Lobby/DM/Nav UX 풀세트 + Sprint 4i 4-테마 시스템 + Bomberman 폭발 자동 클리어/z-order + Snake.io 채팅 fill + Tetris 셀 bevel + 모달 브릿지 머지 후.

## Status

**658 tests, 0 failures**.

```bash
docker compose up -d
MIX_ENV=test bin/mix test
```

## 모듈별 테스트 현황

| 영역 | 모듈 | 케이스 |
|---|---|---|
| 인증 | accounts_test / fetch_current_user_plug_test / ensure_admin_plug_test | 39 |
| 컨트롤러 | registration / session / admin_session / admin / page / error | 40 |
| Friends + Rooms + RateLimit + Chat | friends_test / rooms_test / rate_limit_test / chat_test | 40+ |
| Admin context | admin_test | 8 |
| **Tetris module** | tetris_test (state / SRS / hold / lock delay / combo / B2B / T-spin / garbage / countdown / restart / leave practice / Finesse 통합) | 80+ |
| **Tetris Finesse (Sprint 3i)** | tetris_finesse_test (optimal_count / evaluate / O 회전 무시 / 벽 끝 col 0/9) | 10 |
| **캐치마인드 (Skribbl)** | skribbl_test (state / join / start / choose / stroke / guess / tick / round-robin / total_rounds / word_pool 카테고리 + `:over → leave/restart → :waiting 리셋`) | 34 |
| **Bomberman** | bomberman_test (init / spawn corner / move / place_bomb / fuse / chain / item drop / game_over / `:over → leave/restart → :waiting 리셋`) | 22 |
| **Snake.io** | snake_io_test (meta / init / join / leave / set_dir / 180° 무시 / tick 전진 / 벽 충돌 / 자기 몸 / tail follow 허용 / food eat / kill credit / respawn 60 tick / best_length) | 19 |
| **Pac-Man** | pacman_test (28×31 maze / pellet count / power pellet / ghost AI 4종 / scatter↔chase / frightened / death / restart) | 24 |
| GameSession | game_session_test (lifecycle / dedupe / terminate cleanup / match_record top_out) | 12 |
| 다른 게임 stub | stub_games_test (Bomberman/Snake/Pacman/Skribbl 인터페이스 검증) | 12 |
| 2048 | games_2048_test (board_size 4/5/6 + restart 보존 + 키보드 input) | 25+ |
| 지뢰찾기 (Minesweeper) | minesweeper_test (난이도 easy/medium/hard/custom + clamp + restart + 지뢰찾기 rename + phx-value string→int + cursor 4 방향 + boundary clamp + reveal/flag_cursor) | 27 |
| 스도쿠 (Sudoku) | sudoku_test (meta + 난이도 3종 + random_solution 100번 valid 검증 + fixed/clue 수 + cursor + enter 1-9 + clear + win 조건 + restart) | 22 |
| **Presence (Sprint 4g)** | presence_test (track + lookup / 자동 untrack on process exit / nil ignore / type guard) | 4 |
| **MatchResults** | match_results_test (record/for_user/recent/winners_summary) | 12 |
| **PersonalRecords** | personal_records_test (apply_stats max / metadata merge / leaderboard) | 8 |
| Registry | registry_test | 5 |
| **UserGameSettings** | user_game_settings_test (defaults 모든 게임 / get_for normalize / upsert / reset / list / `2048 → games_2048 alias`) | 18 |
| **Lobby LiveView** | lobby_live_test (인증 / 채팅 / 친구 / 방 / 글로벌 nav / 캐치마인드 badge / 친구 게임 초대 DM 자동 발송) | 29 |
| **DM LiveView** | dm_live_test (인증 / 친구 list / thread mount + mark_read / send / PubSub 실시간 / unread badge / DM bubble URL link / 알림 hook) | 14 |
| **Messages context** | messages_test (send / list_thread / unread_count / mark_thread_read / cap 300+) | 14 |
| **GameEvents (Sprint 4d)** | game_events_test (emit best-effort / Producer 단독 push / dispatch / atom·string event_name / tuple→list) | 8 |
| **Sprint 3j Canvas + Skin** | game_multi_live_test 추가 케이스 (default dom 렌더러 / canvas opt-in 시 phx-hook=TetrisCanvas + data-board JSON + data-skin) + user_game_settings_test (block_skin / tetris_renderer defaults) | 3 |
| **Game Multi LiveView** | game_multi_live_test (Tetris + Skribbl + Bomberman + Snake.io 통합 + 게임방 ephemeral chat broadcast) | 56 |
| **Game Settings LiveView** | game_settings_live_test (인증 / index / Tetris show / 제너릭 폼 / save / reset / `/settings/games/2048` slug alias) | 18 |
| **History LiveView** | history_live_test (인증 / index / leaderboard / invalid slug) | 5 |

## Affected Pages/Routes

- `/` — 게스트 입장
- `/register` — `@trizn.kr` 가입
- `/login` — 로그인
- `/lobby` — 로비 (채팅 / 친구 / 방 / 게임 카테고리 / 🏆 / ⚙️ / 친구 초대)
- `/dm` + `/dm/:peer_id` — DM 1:1 (unread badge / 실시간 알림 / URL 자동 link)
- `/game/:game_type/:room_id` — 멀티 게임 (Tetris ✅, 캐치마인드 ✅)
- `/play/:game_type` — 싱글 (2048, Minesweeper, Pac-Man ✅)
- `/settings/games[/:game_type]` — 사용자 옵션
- `/history` + `/history/leaderboard/:game_type` — 매치 히스토리 / 리더보드
- `/admin/login` — Admin
- 글로벌 top nav (모든 페이지) — `Happy Trizn` + 페이지 타이틀

## Critical Paths

1. **게스트 + 등록자 같은 방 → Tetris 1v1 → 결과** ✅ 테스트
2. **회원가입 → 친구 추가 → 채팅** ✅
3. **Tetris**: 솔로 연습 → 2번째 join → countdown → 1v1 → top_out → 다시 하기
4. **캐치마인드**: 2명 join → 단어 선택 → 그리기 → 정답 → 5라운드 → 우승
5. **호스트 강퇴 → 5분 ban → 재참여** ✅
6. **Admin 로그인 → user ban**
7. **Tetris 상대 leave → 자동 솔로 연습 전환** ✅ 테스트
8. **Skribbl 도구 클릭 → 색/굵기 변경 (event delegation)**
9. **모바일 반응형** ✅ Sprint 3k — 모든 LiveView padding p-3 sm:p-6, DM 단일창 toggle, 게임판 cell 크기 sm: 분기
10. **WebSocket 끊김 → reconnect → 게임 그대로**

## Edge Cases (verified or planned)

- 게스트 닉네임 중복 ✅
- @trizn.kr 대소문자 ✅
- 친구 자기자신 추가 ✅
- 방 max_players 초과 ✅
- 호스트 disconnect → GenServer 종료 + room close ✅
- Tetris 한 명 새로고침 / leave → :practice 자동 전환 ✅
- 캐치마인드 drawer leave → round_end → 다음 drawer ✅
- 메시지 길이 초과 ✅
- 도배 방지 ✅
- 가비지 line clear cancel ✅
- 가비지 overflow 22행 초과 방어 ✅
- 한/영 IME 게임 키 인식 ✅ (e.code 기반)
- 모달 ✕ / backdrop / 저장 후 닫힘 ✅
- 채팅 input 자동 reset (Lobby + Skribbl + DM) ✅
- 채팅창 height 고정 (DM 60vh / 게임방 480px / Skribbl 400px) — overflow scroll, 무한 grow 방지 ✅
- DM body URL `/game/<slug>/<room_id>` 자동 link 분해 ✅
- 친구 초대 — 방 list 에서 modal → 다중 친구 선택 → DM 자동 발송 ✅
- DM unread badge 글로벌 top nav (300+ cap) ✅
- HTTP-only mount → GameSession 미터치 ✅
- GenServer freeze (mailbox 폭주) — perf fix ✅
- match_result dedupe ✅
- GameEvents Broadway 큐 — Producer GenStage + batcher 100/1s, Mongo 다운 시 silent skip ✅
- match_completed 이벤트 game_session 에서 자동 emit ✅
- Tetris Finesse — spawn 직후 piece_inputs 0 리셋 / hold 시 새 piece 도 리셋 / soft_drop·hard_drop·hold 는 finesse 카운트 안 함 ✅
- 모바일 반응형 (Sprint 3k) — DM 단일창 toggle (peer 선택 시 sidebar 숨김 + ← 버튼) / Tetris·Bomberman 셀 크기 sm: 분기 / Snake canvas `max-w-full h-auto` ✅
- Tetris jstris 식 layout (Sprint 3l) — 내 보드 좌측 full (cell w-6 sm:w-7) / 상대 mini board grid (w-3 cell, nickname + top_out ✕ overlay) 우측 위 / 채팅 우측 아래 (height 280px) / grid 라인 base-content/5 (은은) ✅
- Tetris N-player (Sprint 3l-2) — max_players 8, in-progress join 허용 (countdown 안 다시 시작), 가비지 random alive opponent 타겟팅 (top_out 제외, 모두 죽으면 broadcast 안 함) ✅
- Tetris ranking (Sprint 3l-3) — top_out_at monotonic_time 추적, game_over.ranking 정렬 (winner 1등 / 늦게 죽은 사람이 위), 🥇🥈🥉 modal UI ✅
- Tetris live HUD (Sprint 3l-4) — public_player 에 pps/apm/vs/kpp/garbage_sent 포함, 매 lock broadcast 시 갱신, UI grid-cols-3 사이드 패널 ✅
- Bomberman ranking modal (Sprint 3l-6) — game_over.ranking, dead_at monotonic 순서, 🥇🥈🥉 + 본인 row primary highlight + 생존/💥 표시 ✅
- Skribbl ranking modal (Sprint 3l-7) — 점수 내림차순, 🥇🥈🥉 + 본인 row primary highlight + 점수 표시 (Tetris/Bomberman 와 일관) ✅
- Tetris JS Canvas + skin (Sprint 3j) — block_skin 4종 (default_jstris/vivid/monochrome/neon), tetris_renderer "dom" 기본 / "canvas" opt-in, JS hook TetrisCanvas 가 data-board JSON 받아 redraw ✅
- 지뢰찾기 (Sprint 4f) — meta name 한글 "지뢰찾기", phx-value string r/c → int 강제, 화살표 cursor 이동 + boundary clamp + Space/Enter reveal_cursor + F flag_cursor + MinesweeperCell hook 우클릭 ✅
- 스도쿠 (Sprint 3m) — base 패턴 + symmetry transforms (digit perm / row/col swap in band+stack / band/stack swap) → 항상 valid 9×9 solution. 100회 반복 valid 검증, easy 40 / medium 32 / hard 26 clue, cursor 이동 + 1-9 입력 + 0/Backspace clear + 충돌 셀 highlight ✅
- Presence (Sprint 4g) — Phoenix.Presence track / online_user_ids / online?, fetch_live_user hook 자동 track + 연결 종료 시 untrack, presence_diff PubSub 실시간 갱신, Lobby 친구 list + DM 좌측 list + thread header 🟢 dot 표시 ✅
- Lobby UX (Sprint 4h) — 헤더 통합 (root nav 만, lobby 자체 헤더 제거), 닉네임 dropdown (마이페이지/로그아웃), 활성방 페이지네이션 4개/페이지 (← 1 2 3 →), 카드 padding p-3, 친구 섹션 색깔/icon/badge 시각 구분 ✅
- DM UX — 좌(친구 list) 우(채팅창) 모두 h-[70vh] 동기화, 모바일 단일창 toggle, 채팅 input/전송 키움 ✅
- 4 테마 시스템 (Sprint 4i) — Light+ / Dark+ / Night Owl / Hacker Terminal daisyUI 플러그인. `/settings/games` 상단 picker 카드 4개 → `phx:set-theme` JS dispatch, localStorage 저장. 활성 테마 picker 버튼 highlight (`[data-theme=X] .theme-picker-btn[data-phx-theme=X]` CSS). 페이지 새로고침 후 유지. ✅
- Bomberman 폭발 자동 클리어 (Sprint 4i) — `tick/1` 에서 bombs/explosions 활성 시 `:state_changed` PubSub broadcast → catch-all `refresh_state` 트리거. 비활성 시 broadcast 안 함 (50ms tick spam 방지). 사용자 입력 없어도 폭발 ttl (~400ms) 끝나면 화면 자동 갱신. ✅
- Bomberman 폭탄 + 플레이어 z-order (Sprint 4i) — 같은 셀 player + bomb 동시 처리. cell wrapper `relative` + 두 visual 을 absolute 로 겹쳐 player 가 z-10 위. 자기 위치에 폭탄 놓아도 캐릭터 안 사라짐. ✅
- Bomberman 채팅 height (Sprint 4i) — aside `flex flex-col gap-3 min-h-0`, `game_room_chat` 에 `height_class="flex-1 min-h-0"` 패스 → 게임 grid 높이 만큼 늘어남 (기존 280px 고정 → 동적). ✅
- Snake.io 채팅 height (Sprint 4i) — Bomberman 동일 패턴. 캔버스 (640px) 만큼 채팅 늘어남. ✅
- Tetris 셀 inset bevel (Sprint 4i) — `.tetris-filled` (메인 24px) / `.tetris-filled-mini` (opp 12px) `box-shadow`. 빈 셀 무영향. 같은 색 인접 블록끼리 셀 윤곽 분리. ✅
- 전역 옵션 모달 브릿지 (Sprint 4i) — `OpenSettingsBridge` JS hook (`assets/js/app.js`) 게임 LV 컨테이너에 부착, `window.__hasOpenSettingsBridge` flag + `phx:open-settings` window listener → LV `open_settings` push. `root.html.heex` ⚙️ 옵션 anchor onclick 에서 flag 체크. 게임 중 페이지 이동 X, 모달만 열림. 게임 외 페이지에선 기존대로 `/settings/games` 이동. ✅

## E2E 미구현 (계획)

- Playwright 시나리오: 위 1, 3, 4, 7 자동화.
- WebSocket reconnect.
- 모바일 viewport 검증.

## TODO (테스트 커버리지 보강 후보)

- presence diff 받은 후 lobby UI 갱신 통합 테스트 (현재 unit 만 존재)
- 스도쿠 게임 종료 후 elapsed_seconds 측정 정확도
- N-player Tetris 가비지 분산 — 후속 distributor 도입 시 전 케이스
- DM bubble URL 파서 — 다중 URL / 잘못된 slug 등 추가 케이스
- 모바일 viewport 360px chromium headless 캡처 — design QA 자동화
