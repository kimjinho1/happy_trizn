# Test Plan

Branch tracking. 최근 갱신: Sprint 4a (DM + 알림) + 4b (친구 게임 초대) + 4c (채팅창 height 고정) 머지 후.

## Status

**577 tests, 0 failures**.

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
| **Tetris module** | tetris_test (state / SRS / hold / lock delay / combo / B2B / T-spin / garbage / countdown / restart / leave practice) | 75+ |
| **캐치마인드 (Skribbl)** | skribbl_test (state / join / start / choose / stroke / guess / tick / round-robin / total_rounds / word_pool 카테고리 + `:over → leave/restart → :waiting 리셋`) | 34 |
| **Bomberman** | bomberman_test (init / spawn corner / move / place_bomb / fuse / chain / item drop / game_over / `:over → leave/restart → :waiting 리셋`) | 22 |
| **Snake.io** | snake_io_test (meta / init / join / leave / set_dir / 180° 무시 / tick 전진 / 벽 충돌 / 자기 몸 / tail follow 허용 / food eat / kill credit / respawn 60 tick / best_length) | 19 |
| **Pac-Man** | pacman_test (28×31 maze / pellet count / power pellet / ghost AI 4종 / scatter↔chase / frightened / death / restart) | 24 |
| GameSession | game_session_test (lifecycle / dedupe / terminate cleanup / match_record top_out) | 12 |
| 다른 게임 stub | stub_games_test (Bomberman/Snake/Pacman/Skribbl 인터페이스 검증) | 12 |
| 2048 | games_2048_test (board_size 4/5/6 + restart 보존 + 키보드 input) | 25+ |
| Minesweeper | minesweeper_test (난이도 easy/medium/hard/custom + clamp + restart 보존) | 19+ |
| **MatchResults** | match_results_test (record/for_user/recent/winners_summary) | 12 |
| **PersonalRecords** | personal_records_test (apply_stats max / metadata merge / leaderboard) | 8 |
| Registry | registry_test | 5 |
| **UserGameSettings** | user_game_settings_test (defaults 모든 게임 / get_for normalize / upsert / reset / list / `2048 → games_2048 alias`) | 18 |
| **Lobby LiveView** | lobby_live_test (인증 / 채팅 / 친구 / 방 / 글로벌 nav / 캐치마인드 badge / 친구 게임 초대 DM 자동 발송) | 29 |
| **DM LiveView** | dm_live_test (인증 / 친구 list / thread mount + mark_read / send / PubSub 실시간 / unread badge / DM bubble URL link / 알림 hook) | 14 |
| **Messages context** | messages_test (send / list_thread / unread_count / mark_thread_read / cap 300+) | 14 |
| **GameEvents (Sprint 4d)** | game_events_test (emit best-effort / Producer 단독 push / dispatch / atom·string event_name / tuple→list) | 8 |
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
9. **모바일 반응형** (E2E 미작성)
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

## E2E 미구현 (계획)

- Playwright 시나리오: 위 1, 3, 4, 7 자동화.
- WebSocket reconnect.
- 모바일 viewport 검증.
