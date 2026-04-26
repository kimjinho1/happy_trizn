# Design Audit — Happy Trizn (사내 게임 허브)

- **Date**: 2026-04-27
- **URL**: http://localhost:4747
- **Branch**: main
- **Mode**: Standard (5 pages: /, /lobby, /play/sudoku, /play/2048, /dm)
- **Classifier**: APP UI (workspace + 게임 dashboard)
- **Scope**: 수정안만 제시 (auto-fix 안 함, 원래 기능에 지장 없게)

## Headline Scores

| Score | Grade | Verdict |
|---|---|---|
| **Design Score** | **C+** | 기능은 충실, 디테일 미세 정리 다수 필요 |
| **AI Slop Score** | **A-** | jstris/지뢰찾기/2048 클래식 게임 UI — slop 패턴 매우 적음. system-ui 본문 폰트만 1점 감점 |

## First Impression — `/` (entry)

> "사내 게임 허브에 들어왔다. 게스트 입장 / 로그인 / 가입 — 3가지 선택지가 명확하다. 내 눈은 1) 'Happy Trizn' 큰 제목, 2) 주황 '게스트 입장' 버튼, 3) 닉네임 input 으로 차례로 간다. 의도된 hierarchy 와 일치 — 좋다. **One word: 깔끔.**"

**페이지 영역 테스트**: brand / nickname entry / 가입-로그인 alt / admin link 모두 2초 안에 식별 가능. PASS.

## Inferred Design System

- **Font**: `ui-sans-serif, system-ui, sans-serif` 하나뿐 — 본문/제목 모두. **default stack 만 사용 → AI Slop 블랙리스트 #11 (system-ui 가 PRIMARY display/body) 해당. 1점 감점.**
- **Color palette**: orange-600 (primary), gray scale (base-100/200/300), success green, error red, warning yellow — daisyUI 표준 light theme. 12 색 이내, 일관성 OK.
- **Heading scale**: text-lg / text-xl / text-2xl 만 사용. systematic.
- **Spacing**: Tailwind 4px scale (p-1/p-2/p-3 등). systematic.
- **Border radius**: btn / card / input 모두 비슷한 radius — 약간 monotone. 의도적이라 acceptable.
- **Theme**: light only (dark mode 없음).

## Trunk Test 결과 (페이지별)

| Page | Site ID | Page Name | Sections | Where am I | Search | 결과 |
|---|---|---|---|---|---|---|
| `/` (entry) | ✓ | ✓ (Happy Trizn 제목) | ✓ | n/a (single page) | n/a | PASS |
| `/lobby` | ✓ | ✓ (top nav "/ 로비") | ✓ (방 만들기/활성방/친구/채팅) | ✓ | ✗ (search 없음) | PARTIAL — search 없는 건 OK, 하지만 활성방 검색은 후속 |
| `/play/2048`, `/play/sudoku` | ✓ | ✓ | △ (단일 게임이라 sections 없음) | ✓ | n/a | PASS |
| `/dm` (logged-in) | ✓ | ✓ (page_title) | ✓ (대화상대 / thread) | ✓ | ✗ (검색 없음) | PARTIAL |

---

## Findings (impact 순)

### HIGH — F-001 — `/play/*` 페이지 헤더 중복

**Where**: `/play/sudoku`, `/play/2048`, `/play/pacman`, `/play/minesweeper`, `/history`, `/me`, `/settings/games`, `/game/:type/:id`
**Category**: Visual Hierarchy / 일관성
**Severity**: HIGH

**Observation**: 본문 우측 상단에 페이지 자체 헤더가 있다 — `designer_xxx · ⚙️ 옵션 · 로비로`. 그런데 top nav (sticky header) 에도 이미 `🏆 기록 · ⚙️ 옵션 · 닉네임 dropdown` 이 있음. **중복 + 시각 노이즈**. 지난 PR #32 에서 lobby 만 통합했고, 다른 페이지는 안 됐다.

**Why it matters (사용자 영향)**: 같은 액션이 두 곳에 있으면 사용자가 "어느 게 진짜 옵션이지?" 하고 멈춤. 인지 부하 +. 모바일에서는 화면 폭의 25-30% 가 중복 텍스트로 낭비됨.

**Proposed fix (기능 무영향)**:
- `lib/happy_trizn_web/live/game_live.ex` 의 `<header class="flex items-center justify-between mb-4">` 블록 제거 (현재 274~292 line 부근). h1 페이지 제목은 두되 닉네임 + 옵션 + 로비로 버튼 제거.
- 동일하게 `game_multi_live.ex` (멀티 게임 헤더), `history_live.ex`, `profile_live.ex`, `game_settings_live.ex` 도 상단 우측 navigation 부분만 제거.
- 옵션 모달 trigger ⚙️ 옵션 버튼은 top nav `/settings/games` 가 아니라 인라인 modal 이라 **유지 필요** — 단, 페이지 좌측 하단 같은 별도 위치로 옮기거나, page_title h1 옆에 inline 배치하는 게 자연스러움.

**Risk**: 기능 무영향. settings_modal 이미 존재 (PR #31), 그 trigger 위치만 옮김. Tests 일부는 `로비로` text 검사할 가능성 — grep 후 갱신 필요.

---

### HIGH — F-002 — 로비 모바일 카드 wrap 깨짐

**Where**: `/lobby` mobile (375×812)
**Category**: Responsive
**Severity**: HIGH

**Observation**: 활성방 카드의 lock emoji 🔒 가 다음 줄로 떨어짐 (Bomberman/캐치마인드 행). top nav 의 "Happy Trizn" 도 두 줄로 wrap. 모바일에서 단어가 잘리고 layout 망가짐.

**Why it matters**: 사용자가 모바일에서 첫 인상에 "어 깨진 사이트" 느낌. neuf goodwill -10.

**Proposed fix**:
- 활성방 행 — `flex-wrap` 제거 + 내부 `flex-1 min-w-0` 로 game_type badge + 방 이름 truncate. lock emoji 는 inline-flex 로 고정.
- top nav `<a>` Happy Trizn 텍스트에 `whitespace-nowrap` 추가, 모바일에서 `text-sm` 으로 한 단계 줄임.
- "/ 로비" breadcrumb 도 `whitespace-nowrap`.

**Risk**: 무영향. 모두 CSS class 만 변경.

---

### MEDIUM — F-003 — 닉네임 dropdown ▾ 화살표 위치

**Where**: top nav 우측 닉네임 dropdown (`(게스트) designer_xxx ▾`)
**Category**: Interaction states
**Severity**: MEDIUM

**Observation**: ▾ 화살표가 닉네임과 같은 line 에 있어 `text-xs` 라 매우 작음. 게다가 닉네임이 길면 wrap 됨 (게스트 + tail timestamp suffix 의 경우). 사용자 입장에서 dropdown 가능 여부 신호가 약함.

**Why it matters**: dropdown 사용성 — 사용자가 이게 클릭 가능한 메뉴인지 의심.

**Proposed fix**:
- ▾ 를 `text-xs` → `text-sm` 으로 키움.
- 닉네임 `truncate max-w-[120px]` (모바일은 더 짧게).
- 회원가입자는 아바타 + ▾ 만, 닉네임은 `hidden lg:inline`. 게스트는 닉네임 표시.

**Risk**: 무영향. layout 만.

---

### MEDIUM — F-004 — 스도쿠 cursor 셀 색이 갈색-주황 (theme 충돌)

**Where**: `/play/sudoku` cursor highlight (top-left 빈 셀)
**Category**: Color / theme
**Severity**: MEDIUM

**Observation**: `bg-primary/30` 로 cursor 표시인데 light theme 의 primary = orange-600 → 30% alpha 가 갈색-베이지로 렌더링됨. 의도한 "primary blue" feel 안 남. 사용자가 보면 "왜 갈색?" 의문.

**Why it matters**: 스도쿠 cursor 가 가장 자주 보는 요소. 색 의미가 모호하면 시각 혼란.

**Proposed fix**:
- `sudoku_cell_bg(true, ...)` 의 `"bg-primary/30"` → `"bg-info/30 ring-2 ring-info/40"` 로 변경 (info = 파란색).
- 또는 outline 만 사용 (현재 button class 에 이미 `outline outline-2 outline-primary -outline-offset-2` 있음 — bg 자체는 빼고 outline 만으로 cursor 표시).
- 권장: `bg-info/20` 으로 — primary orange 와 의미 충돌 안 함.

**Risk**: 무영향. CSS class 1줄 변경. test 는 `outline-primary` 에만 의존 (line 187 game_live_test) — 통과.

---

### MEDIUM — F-005 — 본문 폰트가 system-ui (정체성 부족)

**Where**: 전체 사이트
**Category**: Typography / brand
**Severity**: MEDIUM (AI Slop 블랙리스트 #11)

**Observation**: `font-family` 가 `ui-sans-serif, system-ui, sans-serif` — 즉 OS 기본 폰트. 사내 도구라 OK 하다고 볼 수도 있지만, **"Happy Trizn" 같은 브랜드 인격**이 폰트로 안 살아남.

**Why it matters**: 사용자가 "익숙한 macOS 시스템 폰트" → 무인격. 게임 허브의 retro/playful 톤과 어울리는 폰트 (예: Pretendard, IBM Plex Sans Mono for game stats, Inter for body) 추가하면 brand 강화.

**Proposed fix**:
- `assets/css/app.css` 에 web font import 추가:
  - 본문/제목: **Pretendard Variable** (한글 가독성 + 모던, 무료)
  - Tetris/Sudoku 숫자: `font-mono` 그대로 (지금 ui-monospace)
  - 게임 제목 / 헤더: 동일 Pretendard, weight 조절로 대비
- daisyUI tailwind config 에 `fontFamily.sans` override.
- 자체 호스팅 (`/assets/fonts/`) — CDN 의존 X.

**Risk**: CSS only. 기능 무영향. 빌드 사이즈 +50~100KB (Pretendard subset). 사내망이라 최초 로드는 거의 무시 가능.

---

### MEDIUM — F-006 — 게스트 친구 영역 visual dead space

**Where**: `/lobby` 우측 친구 카드 (게스트 시)
**Category**: Empty state design
**Severity**: MEDIUM

**Observation**: 게스트로 들어오면 친구 카드에 **"게스트는 친구 기능 사용 불가. @trizn.kr 가입"** 한 줄만 표시되고 나머지 영역은 비어있음. 카드 height 가 거의 풀이라 "왜 이렇게 큰 빈 공간?" 느낌.

**Why it matters**: 게스트 onboarding — 회원가입 유도 기회를 놓침. 빈 카드는 시각적 dead weight.

**Proposed fix**:
- 친구 카드 게스트 empty state 를 적극적으로:
  - 큰 회원가입 버튼 (primary, btn-lg)
  - "회원가입 하면 가능한 것들" 짧은 list (친구 / DM / 영구 기록 / leaderboard)
  - 아이콘 + 짧은 카피 — 마케팅 톤
- 카드 자체 height 는 다른 카드 (글로벌 채팅) 와 맞추기 위해 lg:row-span-2 고려.

**Risk**: 무영향. lobby_live.ex 의 친구 section `is_nil(@user)` 분기 안만 변경.

---

### POLISH — F-007 — 활성방 게임 type badge 일관성

**Where**: `/lobby` 활성방 list
**Category**: Visual hierarchy
**Severity**: POLISH

**Observation**: badge "Snake.io" / "Bomberman" / "캐치마인드" / "Tetris" — 한글/영문 길이 다름 + plain `badge-md` 라 게임 emoji 없음. 좌측 emoji 추가하면 instant-recognition 좋아짐.

**Proposed fix**: badge 안에 게임 emoji prefix 추가 — 지금 싱글 game 버튼 emoji 사용 중인 helper `single_game_emoji/1` 를 multi 도 포함하도록 확장 (`tetris → 🟦`, `bomberman → 💣`, `skribbl → 🎨`, `snake_io → 🐍`).

**Risk**: 무영향. helper 1개 + badge inline.

---

### POLISH — F-008 — 활성방 채팅 카드 사이 visual gap

**Where**: `/lobby` 활성방 ↔ 글로벌 채팅 사이
**Category**: Spacing
**Severity**: POLISH

**Observation**: 두 카드 사이가 `space-y-4` (16px) — 가까운데도 시각적으로 분리. divider 가 살짝 있으면 grouping 더 명확.

**Proposed fix**: 그대로 둬도 OK. polish 차원에서 활성방 카드 아래 `border-b border-base-300` 한 줄 추가하면 시각적 안정.

**Risk**: 무영향.

---

### POLISH — F-009 — 2048 화살표 버튼 layout off-grid

**Where**: `/play/2048`
**Category**: Spacing / layout
**Severity**: POLISH

**Observation**: 4개 화살표 (↑ ← ↓ →) 가 grid 가 아니라 `grid-cols-3` + 빈 div placeholder 로 표시. 2x2 + center cross 구조라 ↑ 가 ← ↓ → 행과 살짝 정렬 어긋난 느낌.

**Proposed fix**: 십자 (cross) 패턴은 keep 하되 button 폭 통일 + grid-template-areas 사용:
```css
grid-template-areas: ". up ." "left down right";
```

**Risk**: 무영향. CSS 만.

---

## Goodwill Reservoir 측정

게스트 사용자 가정 — 입장 → 로비 → 게임 선택까지 walk-through:

```
Goodwill: 70 ████████████████████░░░░░░░░░░
  Step 1: 진입 (게스트 입장 명확)        70 → 80  (+10 obvious primary)
  Step 2: 로비 (활성방 4개 + 싱글 4)     80 → 75  (-5 헤더 중복 — F-001)
  Step 3: 친구 카드 빈 공간              75 → 70  (-5 dead space — F-006)
  Step 4: 스도쿠 진입 (cursor 갈색)       70 → 65  (-5 색 의미 모호 — F-004)
  Step 5: 모바일 lobby 깨짐 (만약 모바일) 65 → 50  (-15 wrap 깨짐 — F-002)
  FINAL (desktop): 65/100  HEALTHY
  FINAL (mobile):  50/100  NEEDS WORK
```

데스크탑 65/100 = healthy, 모바일 50/100 = needs work (F-002 fix 시 65 회복).

---

## Quick Wins (3개 — 30분 안에 가능)

1. **F-001** `/play/*` 페이지 자체 헤더 제거 (5분)
   - game_live.ex header 블록 + 옵션 모달 trigger 위치 조정
   - 모든 game/history/profile/settings live view 동일

2. **F-004** 스도쿠 cursor 색 변경 (1분)
   - `sudoku_cell_bg(true, ...)` orange → info blue

3. **F-002** 로비 모바일 wrap fix (5분)
   - top nav `whitespace-nowrap`
   - 활성방 행 `min-w-0` + truncate

세 fix 모두 CSS only → 기능 무영향 + tests 영향 거의 없음.

---

## TODO 후보 (deferred)

- F-005 Pretendard web font 도입 (디자인 다음 sprint)
- F-006 게스트 친구 카드 회원가입 유도 강화 (마케팅 sprint)
- F-007/008/009 polish — 시간 있을 때
- 다크 모드 (현재 light 만)
- 검색 기능 (활성방 / 친구)

---

## 파일 위치

- 본 보고서: `~/.gstack/projects/kimjinho1-happy_trizn/designs/design-audit-20260427/design-audit-happy_trizn.md`
- 스크린샷: `/Users/kimjinho/Dev/happy_trizn/.gstack-design-audit/`

## PR Summary

> Design audit 9 findings: 2 HIGH + 4 MEDIUM + 3 POLISH. Quick wins (3개) 30분. 모바일 뜸 fix 시 goodwill 50→65. Auto-fix 안 했음 — 수정안만 제시.
